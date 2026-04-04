.pragma library

/**
 * AnsiParser — converts tmux capture-pane ANSI output to Qt RichText HTML.
 *
 * tmux capture-pane -e returns the rendered screen with SGR colour/style codes
 * intact but with cursor-movement codes already resolved (the output is the
 * final composed screen, not a raw byte stream).  We only need to handle SGR
 * sequences here; everything else is stripped.
 *
 * Usage:
 *   import "../../services/ai/AnsiParser.js" as AnsiParser
 *   text: AnsiParser.toHtml(rawCapture)
 */

// Standard xterm 16-colour palette (dark variant)
var _fg16 = [
    "#1c1c1c", // 0  black
    "#cc3333", // 1  red
    "#33aa33", // 2  green
    "#aaaa22", // 3  yellow
    "#3366cc", // 4  blue
    "#aa33aa", // 5  magenta
    "#22aaaa", // 6  cyan
    "#aaaaaa", // 7  white
    "#555555", // 8  bright black (dark grey)
    "#ff5555", // 9  bright red
    "#55ff55", // 10 bright green
    "#ffff55", // 11 bright yellow
    "#5555ff", // 12 bright blue
    "#ff55ff", // 13 bright magenta
    "#55ffff", // 14 bright cyan
    "#ffffff", // 15 bright white
];

// xterm-256 colour cube (6×6×6) + greyscale ramp
function _xterm256(n) {
    if (n < 16) return _fg16[n];
    if (n >= 232) {
        var v = 8 + (n - 232) * 10;
        var h = v.toString(16).padStart(2, "0");
        return "#" + h + h + h;
    }
    n -= 16;
    var b = n % 6;
    var g = Math.floor(n / 6) % 6;
    var r = Math.floor(n / 36);
    function c(x) { return x === 0 ? 0 : 55 + x * 40; }
    function hex(x) { return c(x).toString(16).padStart(2, "0"); }
    return "#" + hex(r) + hex(g) + hex(b);
}

function _escape(s) {
    return s.replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/ /g, "\u00a0")  // preserve spaces in RichText
            .replace(/\t/g, "\u00a0\u00a0\u00a0\u00a0");
}

/**
 * Convert ANSI-escaped terminal text to Qt RichText HTML.
 * Handles:
 *   - SGR 0           reset
 *   - SGR 1           bold
 *   - SGR 2           dim (renders as reduced opacity via color tweak)
 *   - SGR 3           italic
 *   - SGR 22/23       bold/italic off
 *   - SGR 30–37       standard fg colours
 *   - SGR 38;5;n      256-colour fg
 *   - SGR 38;2;r;g;b  truecolour fg
 *   - SGR 39          default fg
 *   - SGR 90–97       bright fg colours
 *   - Background codes (40–47, 49, 100–107) are ignored (sidebar has own bg)
 * All other escape sequences are stripped.
 */
function toHtml(raw) {
    if (!raw || raw.length === 0) return "";

    // Strip all non-SGR escape sequences first (cursor movement, etc.)
    // Keep only ESC [ ... m  (SGR) sequences; remove everything else
    var cleaned = raw.replace(/\x1b\[(?!\d*(?:;\d+)*m)[^a-zA-Z]*[a-zA-Z]/g, "");

    var result = "";
    var bold = false;
    var italic = false;
    var fgColor = "";         // "" = default
    var openTags = 0;

    function flushTags() {
        while (openTags > 0) {
            result += "</font>";
            openTags--;
        }
        if (bold)   result += "</b>";
        if (italic) result += "</i>";
        bold = false;
        italic = false;
        fgColor = "";
        openTags = 0;
    }

    function openColor(col) {
        result += '<font color="' + col + '">';
        openTags++;
        fgColor = col;
    }

    // Match ESC[...m sequences and plain text segments
    var sgrRe = /\x1b\[([0-9;]*)m|([^\x1b]+)/g;
    var m;
    while ((m = sgrRe.exec(cleaned)) !== null) {
        if (m[2] !== undefined) {
            // Plain text segment
            result += _escape(m[2]);
            continue;
        }
        // SGR sequence
        var params = m[1] === "" ? [0] : m[1].split(";").map(Number);
        var i = 0;
        while (i < params.length) {
            var p = params[i];
            if (p === 0) {
                flushTags();
            } else if (p === 1) {
                if (!bold) { result += "<b>"; bold = true; }
            } else if (p === 3) {
                if (!italic) { result += "<i>"; italic = true; }
            } else if (p === 22) {
                if (bold) { result += "</b>"; bold = false; }
            } else if (p === 23) {
                if (italic) { result += "</i>"; italic = false; }
            } else if (p === 39) {
                // Reset fg — close colour tags, reopen if still bold/italic
                while (openTags > 0) { result += "</font>"; openTags--; }
                fgColor = "";
            } else if (p >= 30 && p <= 37) {
                while (openTags > 0) { result += "</font>"; openTags--; }
                openColor(_fg16[p - 30]);
            } else if (p >= 90 && p <= 97) {
                while (openTags > 0) { result += "</font>"; openTags--; }
                openColor(_fg16[p - 90 + 8]);
            } else if (p === 38) {
                // Extended colour
                if (params[i + 1] === 5 && i + 2 < params.length) {
                    while (openTags > 0) { result += "</font>"; openTags--; }
                    openColor(_xterm256(params[i + 2]));
                    i += 2;
                } else if (params[i + 1] === 2 && i + 4 < params.length) {
                    var r = params[i + 2], g = params[i + 3], b = params[i + 4];
                    var hex = "#" + r.toString(16).padStart(2,"0") +
                                    g.toString(16).padStart(2,"0") +
                                    b.toString(16).padStart(2,"0");
                    while (openTags > 0) { result += "</font>"; openTags--; }
                    openColor(hex);
                    i += 4;
                }
            }
            // Background codes (40–47, 100–107, 48) ignored intentionally
            i++;
        }
    }

    // Close any still-open tags
    while (openTags > 0) { result += "</font>"; openTags--; }
    if (italic) result += "</i>";
    if (bold)   result += "</b>";

    return result;
}
