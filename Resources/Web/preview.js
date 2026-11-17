// Runtime for the editor's live preview: code highlighting (Prism), math
// (KaTeX) and diagrams (Mermaid). KaTeX and Mermaid load on first use.
(() => {
  const ASSETS = 'mdp://app/';
  const root = () => document.querySelector('.markdown-body');

  const scripts = {};
  function loadScript(path) {
    return (scripts[path] ||= new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = ASSETS + path;
      s.onload = resolve;
      s.onerror = reject;
      document.head.appendChild(s);
    }));
  }
  function loadStyle(path) {
    if (document.querySelector(`link[data-path="${path}"]`)) return;
    const l = document.createElement('link');
    l.rel = 'stylesheet';
    l.href = ASSETS + path;
    l.dataset.path = path;
    document.head.appendChild(l);
  }

  const dark = () => matchMedia('(prefers-color-scheme: dark)').matches;

  async function renderMath(el) {
    const nodes = el.querySelectorAll('.math:not(.rendered)');
    if (!nodes.length) return;
    loadStyle('vendor/katex/katex.min.css');
    await loadScript('vendor/katex/katex.min.js');
    for (const node of nodes) {
      try {
        katex.render(node.textContent, node, {
          displayMode: node.classList.contains('math-display'),
          throwOnError: false,
        });
        node.classList.add('rendered');
      } catch (e) { /* leave the source visible */ }
    }
  }

  // Rendering a diagram is slow, so SVGs are cached by source and theme
  const diagramCache = new Map();
  let diagramTheme = null;
  let diagramCount = 0;

  async function renderDiagrams(el) {
    const nodes = el.querySelectorAll('pre.mermaid:not([data-processed])');
    if (!nodes.length) return;
    await loadScript('vendor/mermaid.min.js');
    const theme = dark() ? 'dark' : 'default';
    if (theme !== diagramTheme) {
      mermaid.initialize({ startOnLoad: false, theme, securityLevel: 'strict' });
      diagramTheme = theme;
      diagramCache.clear();
    }
    for (const node of nodes) {
      const source = node.textContent;
      let svg = diagramCache.get(source);
      if (!svg) {
        const id = 'mdp-diagram-' + (++diagramCount);
        try {
          ({ svg } = await mermaid.render(id, source));
          diagramCache.set(source, svg);
        } catch (e) {
          document.getElementById('d' + id)?.remove();
          node.dataset.processed = 'error';
          node.title = String(e.message || e);
          continue;
        }
      }
      node.dataset.source = source;
      node.innerHTML = svg;
      node.dataset.processed = 'true';
    }
  }

  let generation = 0;
  async function enhance() {
    const el = root();
    const current = ++generation;
    if (window.Prism) Prism.highlightAllUnder(el);
    await renderMath(el);
    if (current !== generation) return; // a newer update replaced the content
    await renderDiagrams(el);
  }

  window.MDP = {
    update(html) {
      root().innerHTML = html;
      enhance();
    },
    scrollToFraction(f) {
      const max = document.documentElement.scrollHeight - window.innerHeight;
      window.scrollTo(0, max * f);
    },
    // The page as currently shown (highlighted code, rendered math and diagrams), for export
    renderedHTML() {
      return root().innerHTML;
    },
  };

  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    // Re-render diagrams in the new colour scheme
    root().querySelectorAll('pre.mermaid[data-source]').forEach(n => {
      n.textContent = n.dataset.source;
      n.removeAttribute('data-processed');
    });
    enhance();
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', enhance);
  } else {
    enhance();
  }
})();
