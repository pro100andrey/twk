// Text for the HTML of a webview.

/** [s] as text in HTML, also inside a quoted attribute. */
export const escapeHtml = (s: string): string => s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
