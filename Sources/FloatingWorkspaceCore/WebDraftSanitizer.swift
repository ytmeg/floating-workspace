import Foundation

enum WebDraftSanitizer {
    static let messageHandlerName = "floatingWorkspaceDraftIdle"

    private static let helpers = """
        const stateKey = '__floatingWorkspaceWebDraftState';
        const stateFor = () => {
            if (!window[stateKey]) {
                window[stateKey] = {
                    observer: null,
                    timer: null,
                    submitInterceptor: null,
                    editing: false,
                    replayApplied: false
                };
            }
            return window[stateKey];
        };
        const installSubmitInterceptor = state => {
            if (state.submitInterceptor) {
                return;
            }
            state.submitInterceptor = event => {
                event.preventDefault();
                event.stopImmediatePropagation();
            };
            document.addEventListener('submit', state.submitInterceptor, true);
        };
        const removeSubmitInterceptor = state => {
            if (!state.submitInterceptor) {
                return;
            }
            document.removeEventListener('submit', state.submitInterceptor, true);
            state.submitInterceptor = null;
        };
        const stopObserving = state => {
            if (state.observer) {
                state.observer.disconnect();
                state.observer = null;
            }
            if (state.timer !== null) {
                clearTimeout(state.timer);
                state.timer = null;
            }
        };
        const startObserving = state => {
            stopObserving(state);
            if (!document.body) {
                return;
            }
            state.observer = new MutationObserver(() => {
                if (state.timer !== null) {
                    clearTimeout(state.timer);
                }
                state.timer = setTimeout(() => {
                    state.timer = null;
                    window.webkit.messageHandlers.floatingWorkspaceDraftIdle.postMessage({ kind: 'idle' });
                }, 800);
            });
            state.observer.observe(document.body, {
                subtree: true,
                childList: true,
                characterData: true,
                attributes: true
            });
        };
        const sanitizeElement = root => {
            const clone = root.cloneNode(true);
            clone.querySelectorAll('script, iframe, object, embed').forEach(element => element.remove());
            clone.querySelectorAll('meta[http-equiv]').forEach(element => {
                const value = (element.getAttribute('http-equiv') || '').trim().toLowerCase();
                if (value === 'refresh') {
                    element.remove();
                }
            });

            const urlAttributes = new Set(['href', 'src', 'xlink:href', 'action', 'formaction', 'poster', 'data']);
            [clone, ...clone.querySelectorAll('*')].forEach(element => {
                Array.from(element.attributes).forEach(attribute => {
                    const name = attribute.name.toLowerCase();
                    const compactValue = Array.from(attribute.value).filter(character => {
                        return character.charCodeAt(0) > 32;
                    }).join('').toLowerCase();
                    if (name.startsWith('on') || (urlAttributes.has(name) && compactValue.startsWith('javascript:'))) {
                        element.removeAttribute(attribute.name);
                    }
                });
                element.removeAttribute('formaction');
            });
            clone.querySelectorAll('form').forEach(form => {
                form.removeAttribute('action');
                form.removeAttribute('method');
            });
            clone.querySelectorAll('input, button, select').forEach(input => {
                input.removeAttribute('value');
                input.removeAttribute('checked');
            });
            clone.querySelectorAll('textarea').forEach(textarea => {
                textarea.textContent = '';
                textarea.removeAttribute('value');
            });
            clone.querySelectorAll('option').forEach(option => option.removeAttribute('selected'));
            return clone;
        };
        """

    static func setEditing(enabled: Bool) -> String {
        """
        (() => {
            \(helpers)
            const body = document.body;
            if (!body) {
                return { ok: false, reason: 'no-body' };
            }
            const state = stateFor();
            state.editing = \(enabled);
            body.contentEditable = \(enabled) ? 'true' : 'false';
            if (\(enabled)) {
                installSubmitInterceptor(state);
                startObserving(state);
            } else {
                stopObserving(state);
                if (!state.replayApplied) {
                    removeSubmitInterceptor(state);
                }
            }
            return { ok: true, contentEditable: body.contentEditable };
        })()
        """
    }

    static func sanitizeBody() -> String {
        """
        (() => {
            \(helpers)
            if (!document.body) {
                return { ok: false, reason: 'no-body' };
            }
            return { ok: true, html: sanitizeElement(document.body).innerHTML };
        })()
        """
    }

    static func applySanitizedBody(_ html: String) -> String {
        """
        (() => {
            \(helpers)
            const body = document.body;
            if (!body) {
                return { ok: false, reason: 'no-body' };
            }
            const state = stateFor();
            stopObserving(state);
            const parsed = document.implementation.createHTMLDocument('');
            parsed.body.innerHTML = \(javaScriptStringLiteral(for: html));
            body.innerHTML = sanitizeElement(parsed.body).innerHTML;
            state.replayApplied = true;
            installSubmitInterceptor(state);
            if (state.editing) {
                startObserving(state);
            }
            return { ok: true };
        })()
        """
    }

    private static func javaScriptStringLiteral(for value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
}
