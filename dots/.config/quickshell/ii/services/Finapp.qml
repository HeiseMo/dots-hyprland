pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick

Singleton {
    id: root

    property string baseUrl: "http://127.0.0.1:8000"
    property var holdings: []
    property bool loading: false
    property bool loaded: false
    property string errorMessage: ""
    property var lastLoadedAt: null
    property int requestSerial: 0
    property bool refreshInFlight: false
    property bool overviewRequestActive: false

    Timer {
        id: refreshPollTimer
        interval: 2500
        repeat: true
        running: false
        onTriggered: root.refreshOverview(true)
    }

    function refreshOverview(preserveLoading = false) {
        const serial = ++requestSerial;
        const xhr = new XMLHttpRequest();

        root.overviewRequestActive = true;
        if (!preserveLoading)
            root.loading = true;
        root.errorMessage = "";

        xhr.open("GET", `${root.baseUrl}/portfolio/overview`);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 8000;

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || serial !== root.requestSerial)
                return;

            root.overviewRequestActive = false;
            root.loaded = true;

            if (xhr.status < 200 || xhr.status >= 300) {
                root.loading = false;
                root.refreshInFlight = false;
                refreshPollTimer.stop();
                root.holdings = [];
                root.errorMessage = `Could not load holdings from ${root.baseUrl}/portfolio/overview (HTTP ${xhr.status}). Make sure FinApp is already running.`;
                return;
            }

            try {
                const payload = JSON.parse(xhr.responseText);
                if (!Array.isArray(payload))
                    throw new Error("Portfolio overview payload is not a list.");

                root.holdings = root.sortHoldings(payload.map(item => root.normalizeHolding(item)));
                root.lastLoadedAt = new Date();
                root.errorMessage = "";
                const anyRefreshing = root.holdings.some(item => item.refresh_status === "refreshing");
                root.refreshInFlight = anyRefreshing;
                root.loading = anyRefreshing;
                if (anyRefreshing)
                    refreshPollTimer.start();
                else
                    refreshPollTimer.stop();
            } catch (e) {
                root.loading = false;
                root.refreshInFlight = false;
                refreshPollTimer.stop();
                root.holdings = [];
                root.errorMessage = `FinApp returned invalid portfolio data. ${e.message}`;
            }
        };

        xhr.onerror = function() {
            if (serial !== root.requestSerial)
                return;

            root.overviewRequestActive = false;
            root.loading = false;
            root.loaded = true;
            root.refreshInFlight = false;
            refreshPollTimer.stop();
            root.holdings = [];
            root.errorMessage = `Could not reach FinApp at ${root.baseUrl}. Make sure the server is already running.`;
        };

        xhr.ontimeout = function() {
            if (serial !== root.requestSerial)
                return;

            root.overviewRequestActive = false;
            root.loading = false;
            root.loaded = true;
            root.refreshInFlight = false;
            refreshPollTimer.stop();
            root.holdings = [];
            root.errorMessage = `Timed out while loading holdings from ${root.baseUrl}.`;
        };

        xhr.send();
    }

    function refreshPortfolio() {
        const xhr = new XMLHttpRequest();
        root.loading = true;
        root.errorMessage = "";

        xhr.open("POST", `${root.baseUrl}/portfolio/refresh`);
        xhr.setRequestHeader("Accept", "application/json");
        xhr.timeout = 8000;

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;

            if (xhr.status < 200 || xhr.status >= 300) {
                root.loading = false;
                root.refreshInFlight = false;
                refreshPollTimer.stop();
                root.errorMessage = `Could not trigger a FinApp refresh at ${root.baseUrl}/portfolio/refresh (HTTP ${xhr.status}).`;
                return;
            }

            root.refreshInFlight = true;
            root.refreshOverview(true);
        };

        xhr.onerror = function() {
            root.loading = false;
            root.refreshInFlight = false;
            refreshPollTimer.stop();
            root.errorMessage = `Could not reach FinApp at ${root.baseUrl} to trigger a refresh.`;
        };

        xhr.ontimeout = function() {
            root.loading = false;
            root.refreshInFlight = false;
            refreshPollTimer.stop();
            root.errorMessage = `Timed out while triggering a refresh from ${root.baseUrl}.`;
        };

        xhr.send();
    }

    function normalizeHolding(item) {
        return {
            "ticker": `${item?.ticker ?? ""}`.trim(),
            "company_name": `${item?.company_name ?? ""}`.trim(),
            "shares_owned": numberOrNull(item?.shares_owned),
            "last_price": numberOrNull(item?.last_price),
            "market_value": numberOrNull(item?.market_value),
            "unrealized_gain_loss": numberOrNull(item?.unrealized_gain_loss),
            "account_currency": `${item?.account_currency ?? ""}`.trim(),
            "refresh_status": `${item?.refresh_status ?? "idle"}`.trim(),
            "last_error": `${item?.last_error ?? ""}`.trim(),
            "metrics_updated_at": item?.metrics_updated_at ?? null,
        };
    }

    function numberOrNull(value) {
        if (value === null || value === undefined || value === "")
            return null;
        const parsed = Number(value);
        return isNaN(parsed) ? null : parsed;
    }

    function sortHoldings(items) {
        return items.sort((a, b) => {
            const aMarketValue = a.market_value;
            const bMarketValue = b.market_value;

            if (aMarketValue === null && bMarketValue !== null)
                return 1;
            if (aMarketValue !== null && bMarketValue === null)
                return -1;
            if (aMarketValue !== null && bMarketValue !== null && aMarketValue !== bMarketValue)
                return bMarketValue - aMarketValue;

            return `${a.ticker}`.localeCompare(`${b.ticker}`);
        });
    }
}
