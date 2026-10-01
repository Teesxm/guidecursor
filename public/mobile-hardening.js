(() => {
  function enhanceMenus(){
    document.querySelectorAll('.nav-toggle').forEach((toggle,index)=>{
      const nav=toggle.closest('.nav');
      const links=nav?.querySelector('.nav-links');
      if(!links)return;
      if(!links.id)links.id='gc-mobile-nav-'+index;
      toggle.setAttribute('aria-controls',links.id);
      const sync=()=>toggle.setAttribute('aria-expanded',String(links.classList.contains('open')));
      sync();
      toggle.addEventListener('click',()=>requestAnimationFrame(sync));
      document.addEventListener('click',event=>{
        if(!links.classList.contains('open'))return;
        if(nav?.contains(event.target))return;
        links.classList.remove('open');sync();
      });
      document.addEventListener('keydown',event=>{
        if(event.key!=='Escape'||!links.classList.contains('open'))return;
        links.classList.remove('open');sync();toggle.focus();
      });
      addEventListener('orientationchange',()=>{links.classList.remove('open');sync()});
    });
  }

  function labelHorizontalScroll(){
    document.querySelectorAll('.table-wrap,.legal-table-wrap').forEach(el=>{
      el.setAttribute('tabindex','0');
      if(!el.getAttribute('aria-label'))el.setAttribute('aria-label','Horizontally scrollable table');
    });
  }

  function markTouch(){
    const coarse=matchMedia('(pointer: coarse)').matches;
    document.documentElement.classList.toggle('gc-coarse-pointer',coarse);
  }

  function syncVisualViewport(){
    const height=window.visualViewport?.height||window.innerHeight;
    document.documentElement.style.setProperty('--gc-visual-height',Math.max(320,height)+'px');
  }

  function init(){
    enhanceMenus();
    labelHorizontalScroll();
    markTouch();
    syncVisualViewport();
    addEventListener('pageshow',()=>{markTouch();syncVisualViewport()});
    addEventListener('resize',syncVisualViewport,{passive:true});
    window.visualViewport?.addEventListener('resize',syncVisualViewport,{passive:true});
    window.visualViewport?.addEventListener('scroll',syncVisualViewport,{passive:true});
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
