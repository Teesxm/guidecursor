(() => {
  const state = {
    base: document.title || 'GuideCursor',
    context: '',
    system: ''
  };

  function render() {
    const next = state.system || state.context || state.base || 'GuideCursor';
    if (document.title !== next) document.title = next;
  }

  window.GuideCursorTitle = {
    setBase(title) {
      if (!title) return;
      state.base = title;
      render();
    },
    setContext(title) {
      state.context = title || '';
      render();
    },
    clearContext() {
      state.context = '';
      render();
    },
    setSystem(title) {
      state.system = title || '';
      render();
    },
    clearSystem() {
      state.system = '';
      render();
    },
    getState() {
      return { ...state };
    }
  };

  render();
})();