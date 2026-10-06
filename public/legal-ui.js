(() => {
  const COOKIE_NAME='gc_cookie_consent_v1';
  const COOKIE_DAYS=180;
  const DEFAULTS={essential:true,preferences:false,analytics:false,updatedAt:null,version:1};

  function parseCookie(){
    const row=document.cookie.split('; ').find(v=>v.startsWith(COOKIE_NAME+'='));
    if(row){
      try{return {...DEFAULTS,...JSON.parse(decodeURIComponent(row.slice(COOKIE_NAME.length+1)))}}
      catch{}
    }
    try{
      const fallback=localStorage.getItem(COOKIE_NAME);
      return fallback?{...DEFAULTS,...JSON.parse(fallback)}:null;
    }catch{return null}
  }
  function writeCookie(value){
    const payload={...DEFAULTS,...value,essential:true,updatedAt:new Date().toISOString(),version:1};
    const secure=location.protocol==='https:'?'; Secure':'';
    document.cookie=COOKIE_NAME+'='+encodeURIComponent(JSON.stringify(payload))+'; Max-Age='+(COOKIE_DAYS*86400)+'; Path=/; SameSite=Lax'+secure;
    try{localStorage.setItem(COOKIE_NAME,JSON.stringify(payload))}catch{}
    try{window.dispatchEvent(new CustomEvent('guidecursor:consent',{detail:payload}))}catch{}
    return payload;
  }
  function clearCookie(){
    document.cookie=COOKIE_NAME+'=; Max-Age=0; Path=/; SameSite=Lax';
    try{localStorage.removeItem(COOKIE_NAME)}catch{}
  }

  function footer(){
    if(document.querySelector('.gc-site-footer'))return;
    const el=document.createElement('footer');
    el.className='gc-site-footer';
    el.innerHTML=`
      <div class="gc-footer-inner">
        <div class="gc-footer-top">
          <div>
            <a class="gc-footer-brand" href="/"><span class="gc-footer-mark">↖<i></i></span><span>Guide<b>Cursor</b></span></a>
            <div class="gc-footer-copy"><strong>Same software. More reachable.</strong>GuideCursor helps people with low vision or blindness reach the right control in mainstream macOS software while keeping every action their own.</div>
            <span class="gc-footer-status"><i></i> Native macOS · Local by default</span>
          </div>
          <div class="gc-footer-links">
            <div class="gc-footer-col"><small>Product</small><a href="/#product">Product</a><a href="/#how">How it works</a><a href="/scope">Capabilities</a><a href="/funding">For workplaces</a><a href="/prototype">macOS preview</a></div>
            <div class="gc-footer-col"><small>Explore</small><a href="/#demo">Try the interactive preview</a><a href="/#research">Research</a><a href="/help">Help Center</a><a href="/security">Security & Trust</a><a href="/accessibility">Accessibility</a></div>
            <div class="gc-footer-col"><small>Legal</small><a href="/privacy">Privacy</a><a href="/terms">Terms</a><a href="/cookies">Cookie policy</a><button type="button" data-open-cookie-settings>Cookie settings</button></div>
          </div>
        </div>
        <div class="gc-footer-bottom">
          <span>© 2026 GuideCursor</span>
          <div class="gc-footer-bottom-links"><a href="/help">Help</a><a href="/privacy">Privacy</a><a href="/security">Security</a><a href="/terms">Terms</a><a href="/cookies">Cookies</a><a href="/accessibility">Accessibility</a></div>
        </div>
        <span class="gc-footer-cursor" aria-hidden="true">↖</span>
      </div>`;
    document.body.appendChild(el);
  }

  function banner(){
    if(document.querySelector('.gc-consent-banner'))return document.querySelector('.gc-consent-banner');
    const el=document.createElement('div');
    el.className='gc-consent-banner';
    el.hidden=true;
    el.setAttribute('role','region');
    el.setAttribute('aria-label','Cookie preferences');
    el.innerHTML=`
      <div class="gc-consent-message">
        <span class="gc-consent-icon" aria-hidden="true">↖</span>
        <div class="gc-consent-copy"><strong>Your cursor. Your choice.</strong><p>GuideCursor uses essential browser storage to keep the demo working and remember your privacy choice. Optional categories stay off unless you choose them. <a href="/cookies">See what is stored</a>.</p></div>
      </div>
      <div class="gc-consent-actions">
        <button type="button" class="gc-consent-btn manage" data-consent-manage>Manage</button>
        <button type="button" class="gc-consent-btn essential" data-consent-essential>Essential only</button>
        <button type="button" class="gc-consent-btn primary" data-consent-all>Accept all</button>
      </div>`;
    document.body.appendChild(el);
    return el;
  }

  function modal(){
    if(document.querySelector('.gc-consent-modal'))return document.querySelector('.gc-consent-modal');
    const el=document.createElement('div');
    el.className='gc-consent-modal';
    el.hidden=true;
    el.setAttribute('role','dialog');
    el.setAttribute('aria-modal','true');
    el.setAttribute('aria-labelledby','gc-consent-title');
    el.innerHTML=`
      <div class="gc-consent-card">
        <div class="gc-consent-head"><div><span class="gc-consent-kicker">Privacy controls</span><h2 id="gc-consent-title">Choose what stays <span>on.</span></h2></div><button class="gc-consent-close" type="button" aria-label="Close cookie settings">×</button></div>
        <p class="gc-consent-intro">Essential storage supports requested site features. Optional categories require your choice. This website currently loads no advertising tracker and no third-party analytics SDK.</p>
        <div class="gc-consent-category"><div><strong>Essential storage</strong><p>Remembers this consent choice and acknowledged site updates. These features cannot be disabled here because the site uses them to provide the requested experience.</p></div><span class="gc-consent-always">Always on</span></div>
        <div class="gc-consent-category"><div><strong>Preferences</strong><p>Allows the site to remember optional experience choices. Enabling this records your preference only; no sensitive accessibility profile is stored.</p></div><label class="gc-switch"><input id="gc-consent-preferences" type="checkbox"><span></span></label></div>
        <div class="gc-consent-category"><div><strong>Analytics</strong><p>Permission for privacy-preserving site measurement. No external analytics provider is currently loaded, even if you enable this category.</p></div><label class="gc-switch"><input id="gc-consent-analytics" type="checkbox"><span></span></label></div>
        <div class="gc-consent-note"><b>No dark patterns.</b> “Essential only” is available at the same level as “Accept all”, optional toggles start off, and you can change your choice from the footer at any time.</div>
        <div class="gc-consent-modal-actions"><button type="button" class="gc-consent-btn essential" data-modal-essential>Use essential only</button><button type="button" class="gc-consent-btn primary" data-modal-save>Save my choices</button></div>
      </div>`;
    document.body.appendChild(el);
    return el;
  }

  let modalScrollY=0;
  function lockPageForModal(){
    modalScrollY=window.scrollY||window.pageYOffset||0;
    document.documentElement.style.overflow='hidden';
    document.body.style.position='fixed';
    document.body.style.top='-'+modalScrollY+'px';
    document.body.style.left='0';
    document.body.style.right='0';
    document.body.style.width='100%';
  }
  function unlockPageForModal(){
    document.documentElement.style.overflow='';
    document.body.style.position='';
    document.body.style.top='';
    document.body.style.left='';
    document.body.style.right='';
    document.body.style.width='';
    window.scrollTo(0,modalScrollY);
  }

  function toast(message='Privacy preferences saved'){
    let el=document.querySelector('.gc-consent-toast');
    if(!el){el=document.createElement('div');el.className='gc-consent-toast';document.body.appendChild(el)}
    el.textContent=message;el.classList.add('show');setTimeout(()=>el.classList.remove('show'),2200);
  }
  function openSettings(){
    const m=modal(),value=parseCookie()||DEFAULTS;
    m.querySelector('#gc-consent-preferences').checked=!!value.preferences;
    m.querySelector('#gc-consent-analytics').checked=!!value.analytics;
    m.hidden=false;
    lockPageForModal();
    requestAnimationFrame(()=>m.querySelector('.gc-consent-close')?.focus());
  }
  function closeSettings(){
    const m=modal();if(m.hidden)return;
    m.hidden=true;unlockPageForModal();
  }
  function accept(value){
    writeCookie(value);
    banner().hidden=true;
    closeSettings();
    toast();
  }

  function bind(){
    const b=banner(),m=modal();
    b.querySelector('[data-consent-all]').addEventListener('click',()=>accept({preferences:true,analytics:true}));
    b.querySelector('[data-consent-essential]').addEventListener('click',()=>accept({preferences:false,analytics:false}));
    b.querySelector('[data-consent-manage]').addEventListener('click',openSettings);
    m.querySelector('.gc-consent-close').addEventListener('click',closeSettings);
    m.querySelector('[data-modal-essential]').addEventListener('click',()=>accept({preferences:false,analytics:false}));
    m.querySelector('[data-modal-save]').addEventListener('click',()=>accept({preferences:m.querySelector('#gc-consent-preferences').checked,analytics:m.querySelector('#gc-consent-analytics').checked}));
    m.addEventListener('click',e=>{if(e.target===m)closeSettings()});
    document.addEventListener('click',e=>{const trigger=e.target.closest?.('[data-open-cookie-settings]');if(trigger){e.preventDefault();openSettings()}});
    document.addEventListener('keydown',e=>{if(e.key==='Escape'&&!m.hidden)closeSettings()});
  }

  function init(){
    footer();bind();
    if(!parseCookie())setTimeout(()=>{banner().hidden=false},700);
  }

  window.GuideCursorConsent={
    read:parseCookie,
    open:openSettings,
    save:writeCookie,
    clear(){clearCookie();banner().hidden=false;toast('Privacy choice cleared')},
    resetLocalDemoData(){
      const keepCookie=parseCookie();
      const keys=[];
      for(let i=0;i<localStorage.length;i++){const k=localStorage.key(i);if(k&&(k.startsWith('gc:')||k.startsWith('gc_')))keys.push(k)}
      keys.forEach(k=>localStorage.removeItem(k));
      if(keepCookie)try{localStorage.setItem(COOKIE_NAME,JSON.stringify(keepCookie))}catch{}
      toast('Local demo data cleared');
    }
  };

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
