import QtQuick

ApiStrategy {
    function buildEndpoint(model) {
        return ""
    }

    function buildRequestData(model, messages, systemPrompt, temperature, tools, filePath) {
        const transcript = [
            systemPrompt && systemPrompt.length > 0 ? `System:\n${systemPrompt}` : "",
            ...messages.map(message => {
                const role = message.role === "assistant" ? "Assistant" : "User";
                return `${role}:\n${message.rawContent}`;
            })
        ].filter(Boolean).join("\n\n---\n\n");

        return {
            prompt: transcript,
            cwd: model.extraParams?.cwd || "",
            model: model.model || "sonnet",
            binaryPath: model.extraParams?.binary_path || "",
            permissionMode: model.extraParams?.permission_mode || "plan",
        };
    }

    function buildAuthorizationHeader(apiKeyEnvVarName) {
        return ""
    }

    function appendText(message, text) {
        if (!text || text.length === 0)
            return;
        message.rawContent += text;
        message.content += text;
    }

    function extractContentText(content) {
        if (typeof content === "string")
            return content;
        if (Array.isArray(content)) {
            return content.map(part => {
                if (part?.type === "text")     return part.text ?? "";
                if (part?.type === "thinking") return "<think>" + (part.thinking ?? "") + "</think>";
                return "";
            }).join("");
        }
        return "";
    }

    function buildStdinMessage(text) {
        return JSON.stringify({
            type: "user",
            message: { role: "user", content: [{ type: "text", text: text }] }
        });
    }

    function isTurnComplete(data) {
        return data?.type === "result";
    }

    function extractToolCalls(content) {
        if (!Array.isArray(content)) return [];
        return content
            .filter(part => part?.type === "tool_use" && part?.name)
            .map(part => {
                const inp = part.input ?? {};
                const target = inp.file_path ?? inp.command ?? inp.pattern ?? inp.path ?? inp.query ?? inp.url ?? "";
                return {
                    id: part.id ?? "",
                    name: part.name,
                    target: target,
                    input: inp,         // full input for expandable detail
                    output: "",         // filled in from tool_result events
                    expanded: false,
                };
            });
    }

    function parseResponseLine(line, message) {
        const clean = line.trim();
        if (!clean)
            return {};

        try {
            const data = JSON.parse(clean);
            const type = data.type || "";

            if (type === "assistant") {
                const content = data.message?.content;
                // Extract text and thinking blocks
                const text = extractContentText(content);
                if (text) appendText(message, text);
                // Extract tool calls with full input + id
                const calls = extractToolCalls(content);
                if (calls.length > 0)
                    message.toolCalls = [...(message.toolCalls ?? []), ...calls];

            } else if (type === "user") {
                // Tool results — match by tool_use_id and store stdout/stderr
                const content = data.message?.content;
                const toolResult = data.tool_use_result;  // {stdout, stderr, interrupted, isImage}
                if (Array.isArray(content)) {
                    for (const part of content) {
                        if (part?.type !== "tool_result" || !part?.tool_use_id) continue;
                        const calls = message.toolCalls ?? [];
                        const idx = calls.findIndex(c => c.id === part.tool_use_id);
                        if (idx < 0) continue;
                        // Build output from tool_use_result (richer) or content string fallback
                        let output = "";
                        if (toolResult) {
                            const stdout = (toolResult.stdout ?? "").trim();
                            const stderr = (toolResult.stderr ?? "").trim();
                            output = stdout;
                            if (stderr) output += (output ? "\n[stderr]\n" : "[stderr]\n") + stderr;
                        } else if (typeof part.content === "string") {
                            output = part.content;
                        } else if (Array.isArray(part.content)) {
                            output = part.content
                                .filter(p => p?.type === "text")
                                .map(p => p.text ?? "")
                                .join("\n");
                        }
                        const updated = [...calls];
                        updated[idx] = Object.assign({}, updated[idx], { output: output });
                        message.toolCalls = updated;
                    }
                }

            } else if (type === "result") {
                // Only use result text as fallback if no content came through assistant events
                if (!message.rawContent || message.rawContent.length === 0)
                    appendText(message, data.result ?? "");
                return { finished: true };
            }
        } catch (e) {
            // Ignore non-JSON noise from the CLI.
        }

        return {};
    }

    function onRequestFinished(message) {
        return {};
    }

    function reset() {}

    function buildScriptFileSetup(filePath) {
        return "";
    }

    function finalizeScriptContent(scriptContent) {
        return scriptContent;
    }
}
