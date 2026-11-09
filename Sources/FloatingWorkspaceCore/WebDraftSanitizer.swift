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
                window.webkit.messageHandlers.floatingWorkspaceDraftIdle.postMessage({ kind: 'dirty' });
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
        const urlAttributes = new Set(['href', 'src', 'xlink:href', 'action', 'formaction', 'poster', 'data']);
        const activeElementNames = new Set([
            'script', 'iframe', 'object', 'embed', 'frame', 'frameset',
            'portal', 'applet', 'base', 'set', 'animate',
            'noscript', 'noembed', 'noframes'
        ]);
        const sanitizeTree = root => {
            const elements = root.nodeType === 1 ? [root, ...root.querySelectorAll('*')] : [...root.querySelectorAll('*')];
            elements.forEach(element => {
                const localName = element.localName.toLowerCase();
                if (localName === 'set' || localName === 'animate') {
                    const target = (element.getAttribute('attributeName') || '').toLowerCase();
                    if (urlAttributes.has(target)) {
                        ['to', 'values', 'from', 'by'].forEach(name => element.removeAttribute(name));
                    }
                }
                if (activeElementNames.has(localName)) {
                    element.remove();
                    return;
                }
                if (localName === 'meta') {
                    const refresh = (element.getAttribute('http-equiv') || '').trim().toLowerCase();
                    if (refresh === 'refresh') {
                        element.remove();
                        return;
                    }
                }

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
                element.removeAttribute('formmethod');
                element.removeAttribute('formtarget');
                element.removeAttribute('ping');
                if (localName === 'form') {
                    element.removeAttribute('action');
                    element.removeAttribute('method');
                }
                if (localName === 'input' || localName === 'button' || localName === 'select') {
                    element.removeAttribute('value');
                    element.removeAttribute('checked');
                }
                if (localName === 'textarea') {
                    element.textContent = '';
                    element.removeAttribute('value');
                }
                if (localName === 'option') {
                    element.removeAttribute('selected');
                }
            });
            elements.forEach(element => {
                if (element.localName.toLowerCase() === 'template') {
                    sanitizeTree(element.content);
                }
            });
        };
        const sanitizeElement = root => {
            const clone = root.cloneNode(true);
            sanitizeTree(clone);
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
            if (\(enabled)) {
                state.editing = true;
                body.contentEditable = 'true';
                installSubmitInterceptor(state);
                startObserving(state);
            } else {
                stopObserving(state);
                state.editing = false;
                body.contentEditable = 'false';
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
            const sanitized = sanitizeElement(parsed.body);
            // Move nodes with importNode instead of re-serializing: serializing the inert
            // document would turn noscript children into markup that the live document
            // parses as raw text, which can break out into active elements.
            body.replaceChildren(...Array.from(
                sanitized.childNodes,
                node => document.importNode(node, true)
            ));
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
