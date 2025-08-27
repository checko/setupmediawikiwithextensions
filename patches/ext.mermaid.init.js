/* Minimal Mermaid initializer for MediaWiki RL */
(function(){
  function decodeHtmlEntities(str){
    var textarea=document.createElement('textarea');
    textarea.innerHTML=str; return textarea.value;
  }
  function ensureMermaid(cb){
    if (window.mermaid){ cb(); return; }
    var s=document.createElement('script');
    // Load local copy to avoid CDN/network issues
    s.src='/extensions/Mermaid/resources/mermaid.min.js';
    s.onload=function(){ cb(); };
    s.onerror=function(){ console.error('[Mermaid] failed to load library'); };
    document.head.appendChild(s);
  }
  function renderAll(){
    if (!window.mermaid){ console.warn('[Mermaid] library missing'); return; }
    var items=document.querySelectorAll('.ext-mermaid');
    Array.prototype.forEach.call(items, function(item, index){
      var st = item.getAttribute('data-mermaid-status');
      if (st === 'rendering' || st === 'rendered') { return; }
      // Lock to avoid double render from multiple hooks
      item.setAttribute('data-mermaid-status','rendering');
      var id='ext-mermaid-'+Math.random().toString(36).slice(2,10)+'-'+index;
      var data={};
      try { data = typeof item.dataset.mermaid==='string' ? JSON.parse(item.dataset.mermaid) : {}; } catch(e){ console.error('[Mermaid] bad data-mermaid', e); return; }
      if (!data.content || typeof data.content!=='string'){ console.error('[Mermaid] no content'); return; }
      var dots=item.children[0]; if (dots) dots.style.display='none';
      var cfg=(data && data.config) ? data.config : {};
      try { window.mermaid.initialize(cfg); } catch(e){ /* ignore */ }
      var code=decodeHtmlEntities(data.content);
      // Remove any previous graph child to avoid duplicates
      Array.prototype.slice.call(item.querySelectorAll('.mermaid-graph, [id^="ext-mermaid-"]')).forEach(function(node){ node.remove(); });
      var graph=document.createElement('div'); graph.className='mermaid-graph'; graph.id=id;
      try {
        if (typeof window.mermaid.render==='function' && window.mermaid.render.length>=3){
          window.mermaid.render(id+'-svg', code, function(svg, bindFunctions){
            graph.innerHTML=svg; item.appendChild(graph);
            if (typeof bindFunctions==='function') bindFunctions(graph);
            item.setAttribute('data-mermaid-status','rendered');
          });
        } else {
          var p=window.mermaid.render(id+'-svg', code);
          if (p && typeof p.then==='function'){
            p.then(function(res){ graph.innerHTML=res.svg; item.appendChild(graph); if (res.bindFunctions) res.bindFunctions(graph); item.setAttribute('data-mermaid-status','rendered'); })
             .catch(function(err){ console.error('[Mermaid] render failed', err); item.setAttribute('data-mermaid-status','rendered'); });
          }
        }
      } catch(e){ console.error('[Mermaid] render error', e); }
    });
  }
  function ready(){ ensureMermaid(renderAll); }
  if (typeof mw!=='undefined' && mw.hook){
    mw.hook('wikipage.content').add(ready);
  } else {
    if (document.readyState==='loading'){ document.addEventListener('DOMContentLoaded', ready); } else { ready(); }
  }
})();
