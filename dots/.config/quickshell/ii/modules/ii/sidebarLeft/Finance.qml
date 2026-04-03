import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property real padding: 4
    property bool requestedInitialLoad: false
    property bool isActive: false

    function ensureLoaded() {
        if (root.requestedInitialLoad)
            return;

        root.requestedInitialLoad = true;
        Finapp.refreshPortfolio();
    }

    function formatNumber(value, decimals = 2) {
        if (value === null || value === undefined)
            return "—";
        return Number(value).toLocaleString(Qt.locale(), "f", decimals);
    }

    function formatCurrency(value, currency) {
        if (value === null || value === undefined)
            return "—";
        const currencyCode = currency && currency.length > 0 ? currency : "EUR";
        return `${currencyCode} ${formatNumber(value, 2)}`;
    }

    function formatDateTime(value) {
        if (!value)
            return "Unknown update time";

        const date = new Date(value);
        if (isNaN(date.getTime()))
            return "Unknown update time";

        return Qt.locale().toString(date, "dd MMM yyyy, hh:mm");
    }

    function gainLossColor(value) {
        if (value === null || value === undefined)
            return Appearance.colors.colSubtext;
        if (value > 0)
            return Appearance.m3colors.m3success;
        if (value < 0)
            return Appearance.colors.colError;
        return Appearance.colors.colSubtext;
    }

    function prettyStatus(status) {
        const clean = `${status ?? ""}`.trim();
        if (clean.length === 0)
            return "Idle";
        if (clean === "missing_price")
            return "Missing price";
        if (clean === "refreshing")
            return "Refreshing";
        if (clean === "ready")
            return "Ready";
        if (clean === "stale")
            return "Stale";
        if (clean === "error")
            return "Error";
        const normalized = clean.replace(/_/g, " ");
        return normalized.charAt(0).toUpperCase() + normalized.slice(1);
    }

    onIsActiveChanged: {
        if (isActive)
            root.ensureLoaded();
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Toolbar {
            Layout.fillWidth: true
            enableShadow: false

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Portfolio")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.normal
                    variableAxes: Appearance.font.variableAxes.title
                }
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                visible: Finapp.lastLoadedAt !== null && !Finapp.loading
                text: Translation.tr("Updated %1").arg(root.formatDateTime(Finapp.lastLoadedAt))
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }

            IconToolbarButton {
                text: "refresh"
                enabled: !Finapp.loading
                onClicked: Finapp.refreshPortfolio()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PagePlaceholder {
                anchors.fill: parent
                shown: Finapp.loading
                icon: "monitoring"
                title: Translation.tr("Loading portfolio")
                description: Translation.tr("Fetching your holdings from FinApp...")
                shape: MaterialShape.Shape.Cookie7
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - root.padding * 4, 420)
                spacing: 10
                visible: !Finapp.loading && Finapp.errorMessage.length > 0

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "finance"
                    shape: MaterialShape.Shape.Cookie7
                    padding: 12
                    iconSize: 56
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Finance unavailable")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.larger
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                }

                NoticeBox {
                    Layout.fillWidth: true
                    materialIcon: "info"
                    text: Translation.tr("%1\n\nExpected base URL: %2\n\nFinApp needs to already be running.\n\nStart it from /home/ttanurhan/projects/finapp with:\nuvicorn app.main:app --reload")
                        .arg(Finapp.errorMessage)
                        .arg(Finapp.baseUrl)
                }
            }

            PagePlaceholder {
                anchors.fill: parent
                shown: !Finapp.loading && Finapp.errorMessage.length === 0 && Finapp.loaded && Finapp.holdings.length === 0
                icon: "finance"
                title: Translation.tr("No holdings yet")
                description: Translation.tr("FinApp responded successfully, but there are no portfolio positions to show.")
                shape: MaterialShape.Shape.Cookie7
            }

            StyledListView {
                id: holdingsList
                anchors.fill: parent
                visible: !Finapp.loading && Finapp.errorMessage.length === 0 && Finapp.holdings.length > 0
                spacing: 8
                clip: true
                model: Finapp.holdings
                delegate: Rectangle {
                    required property var modelData
                    width: holdingsList.width
                    implicitHeight: contentLayout.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: contentLayout
                        anchors {
                            fill: parent
                            margins: 10
                        }
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                text: modelData.ticker
                                font {
                                    family: Appearance.font.family.title
                                    pixelSize: Appearance.font.pixelSize.large
                                    variableAxes: Appearance.font.variableAxes.title
                                }
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.company_name
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                            }

                            StyledText {
                                text: root.prettyStatus(modelData.refresh_status)
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colSubtext
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 14
                            rowSpacing: 6

                            StyledText {
                                text: Translation.tr("Shares · %1").arg(root.formatNumber(modelData.shares_owned, 2))
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: Translation.tr("Price · %1").arg(root.formatCurrency(modelData.last_price, modelData.account_currency))
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                text: Translation.tr("Value · %1").arg(root.formatCurrency(modelData.market_value, modelData.account_currency))
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: Translation.tr("P/L · %1").arg(root.formatCurrency(modelData.unrealized_gain_loss, modelData.account_currency))
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: root.gainLossColor(modelData.unrealized_gain_loss)
                            }
                        }

                        StyledText {
                            visible: modelData.last_error && modelData.last_error.length > 0
                            Layout.fillWidth: true
                            text: modelData.last_error
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colError
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Metrics updated · %1").arg(root.formatDateTime(modelData.metrics_updated_at))
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            color: Appearance.colors.colSubtext
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
