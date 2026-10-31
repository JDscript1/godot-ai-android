// Functional DOM/focus unit tests. Input focus and trusted gestures are simulated;
// this does not establish rendering or Android keyboard behavior.
import fs from 'node:fs';
import vm from 'node:vm';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {parseHTML}=require(process.env.ZIVA_DOM_MODULE || 'linkedom');
const script=fs.readFileSync('platform/android/java/editor/src/main/assets/ai/ziva-mobile.js','utf8');
const {window,document,HTMLElement,Element,MutationObserver,Event}=parseHTML(`<!doctype html><html><head></head><body><header><button data-testid="open-settings-button">Settings</button></header><div data-testid="chat-header-panels"><div>Details</div></div><div data-message-scroller-viewport>Messages</div><section><form><div data-slot="input-group-control"><div data-testid="composer-input" contenteditable="true" tabindex="0"><p>Draft</p></div></div><button data-testid="composer-send">Send</button></form></section><div id="dialog"><input type="password" id="key"></div></body></html>`);
let active=document.body;let now=10000;let checks=0;
const listeners=new Map();
const add=document.addEventListener.bind(document);
document.addEventListener=(name,fn,...rest)=>{if(!listeners.has(name))listeners.set(name,[]);listeners.get(name).push(fn);add(name,fn,...rest)};
Object.defineProperty(document,'activeElement',{get:()=>active});
HTMLElement.prototype.focus=function(){active=this;this.dispatchEvent(new Event('focusin',{bubbles:true}))};
HTMLElement.prototype.blur=function(){if(active===this)active=document.body};
let delayedMicrophone=false;let resolveMicrophone;
const track=()=>({readyState:'live',stops:0,stop(){this.stops++;this.readyState='ended'},addEventListener(){}});
let microphoneTrack=track();
const mediaDevices={getUserMedia:async constraints=>{
  if(delayedMicrophone)return new Promise(resolve=>{resolveMicrophone=resolve});
  return {getTracks:()=>[microphoneTrack]};
}};
const originalFocus=HTMLElement.prototype.focus;
const context={window,document,HTMLElement,Element,MutationObserver,DOMException,navigator:{mediaDevices},performance:{now:()=>now},requestAnimationFrame:fn=>setImmediate(fn)};
vm.runInNewContext(script,context);
const check=(ok,label)=>{if(!ok)throw Error(label);checks++};
const gesture=(name,target,extra={})=>(listeners.get(name)||[]).forEach(fn=>fn({target,isTrusted:true,...extra}));
const input=document.querySelector('[data-testid="composer-input"]');
const field=document.querySelector('#key');
check(document.querySelectorAll('#godot-ziva-mobile-style').length===1,'Installs one host stylesheet');
check(HTMLElement.prototype.focus===originalFocus,'Host never replaces the focus primitive used by Lexical and Android IME');
check(input.closest('form').hasAttribute('data-godot-ziva-composer'),'Composer recognized through the official test ID');
check(input.closest('section').hasAttribute('data-godot-ziva-composer-region'),'Composer notices bounded separately from messages');
check(document.querySelector('header').hasAttribute('data-godot-ziva-header'),'Official header recognized');
input.focus();check(active===document.body&&!window.__godotZivaWantsKeyboard(),'Blocks upstream startup focus');
gesture('pointerdown',input.firstElementChild);input.focus();check(active===input&&window.__godotZivaWantsKeyboard(),'Direct tap inside lexical paragraph permits editing');
gesture('pointerdown',document.querySelector('[data-testid="composer-send"]'));
input.focus();check(active===document.body&&!window.__godotZivaWantsKeyboard(),'Send blocks an asynchronous composer refocus');
gesture('pointerdown',document.querySelector('[data-testid="open-settings-button"]'));
field.focus();check(active===document.body,'Settings cannot autofocus its text field');
gesture('pointerdown',field);field.focus();check(active===field&&window.__godotZivaWantsKeyboard(),'Intentional settings field selection works');
window.__godotZivaDismissKeyboard();input.focus();check(active===document.body&&!window.__godotZivaWantsKeyboard(),'Hiding the host clears stale editing intent');
gesture('keydown',document.body,{key:'Tab'});field.focus();check(active===field,'Physical keyboard Tab navigation works');
now+=1500;window.__godotZivaDismissKeyboard();input.focus();check(active===document.body,'Tab authorization expires');
gesture('pointerdown',input);input.focus();gesture('compositionstart',input);
input.firstElementChild.textContent='pădure';input.focus();gesture('compositionend',input);
check(active===input&&input.textContent==='pădure'&&window.__godotZivaWantsKeyboard(),'Repeated editor focus during composition preserves the text and editing session');
gesture('click',input);check(active===input&&window.__godotZivaWantsKeyboard(),'Trusted accessibility activation can edit');
gesture('submit',input.closest('form'));input.focus();check(active===document.body,'Submit clears editing intent');
const toggle=document.querySelector('#godot-ziva-panels-toggle');check(!!toggle,'Extra panels remain available through a button');
toggle.click();check(document.querySelector('[data-testid="chat-header-panels"]').hasAttribute('data-godot-expanded'),'Panel expands');
toggle.click();check(toggle.getAttribute('aria-expanded')==='false','Panel collapses with accessibility state');
vm.runInNewContext(script,context);check(document.querySelectorAll('#godot-ziva-mobile-style').length===1,'Page-finished and commit callbacks are idempotent');
const extra=document.createElement('div');extra.innerHTML='<form><div data-testid="composer-input" contenteditable="true"></div></form>';
input.closest('section').remove();document.body.append(extra);
await new Promise(r=>setTimeout(r,40));
check(extra.firstElementChild.hasAttribute('data-godot-ziva-composer'),'Observer adapts replacement composer after SPA navigation');
const oldEditor=extra.querySelector('[contenteditable]');gesture('pointerdown',oldEditor);oldEditor.focus();gesture('compositionstart',oldEditor);
const replacement=document.createElement('div');replacement.setAttribute('contenteditable','true');replacement.setAttribute('data-testid','composer-input');replacement.textContent='română';
oldEditor.replaceWith(replacement);replacement.focus();gesture('compositionend',replacement);
check(active===replacement&&replacement.textContent==='română'&&window.__godotZivaWantsKeyboard(),'Replacing a composer DOM node during an edit cannot revoke microphone-independent keyboard intent');
const panels=document.querySelector('[data-testid="chat-header-panels"]');panels.innerHTML='';
await new Promise(r=>setTimeout(r,40));check(!document.querySelector('#godot-ziva-panels-toggle'),'Empty panels do not leave a toolbar taking space');
await mediaDevices.getUserMedia({audio:true});window.__godotZivaReleaseMicrophone();
check(microphoneTrack.stops===1,'Leaving the tab releases acquired microphone tracks');
delayedMicrophone=true;microphoneTrack=track();const late=mediaDevices.getUserMedia({audio:true});
window.__godotZivaReleaseMicrophone();resolveMicrophone({getTracks:()=>[microphoneTrack]});
let cancelled=false;try{await late}catch(error){cancelled=error.name==='AbortError'}
check(cancelled&&microphoneTrack.stops===1,'A pending capture resolving after tab hide is cancelled and releases its audio');

// Reproduce the observed WebView failure: a successful native insertion into
// the same Text node returns a collapsed selection at zero. No editor model is
// mocked here; the host may correct the selection, never the inserted text.
let ranges=0;
const selection={anchorNode:null,focusNode:null,anchorOffset:0,focusOffset:0,
 get isCollapsed(){return this.anchorNode===this.focusNode&&this.anchorOffset===this.focusOffset},
 removeAllRanges(){},addRange(range){this.anchorNode=this.focusNode=range.startContainer;this.anchorOffset=this.focusOffset=range.startOffset}};
window.getSelection=()=>selection;
document.createRange=()=>{ranges++;return {startContainer:null,startOffset:0,setStart(node,offset){this.startContainer=node;this.startOffset=offset},collapse(){}}};
function nativeInsert({before='v',start=1,end=start,data='e',after,afterOffset=0,inputType='insertText',composing=false,trusted=true,target=replacement,targetRange=false,replaceNode=false}){
 replacement.textContent=before;
 const node=replacement.firstChild;
 selection.anchorNode=selection.focusNode=node;selection.anchorOffset=start;selection.focusOffset=end;
 const first=Math.min(start,end),last=Math.max(start,end);
 const expected=after??before.slice(0,first)+data+before.slice(last);
 const extra={inputType,data,isComposing:composing,isTrusted:trusted};
 if(targetRange)extra.getTargetRanges=()=>[{startContainer:node,endContainer:node,startOffset:targetRange[0],endOffset:targetRange[1]}];
 gesture('beforeinput',target,extra);
 if(replaceNode)replacement.textContent=expected;else node.nodeValue=expected;
 selection.anchorNode=selection.focusNode=replaceNode?replacement.firstChild:node;
 selection.anchorOffset=selection.focusOffset=afterOffset;
 gesture('input',target,extra);
 return {text:replacement.textContent,offset:selection.anchorOffset};
}
let word='v';
for(const letter of 'erifica'){
 const result=nativeInsert({before:word,start:word.length,data:letter});word+=letter;
 check(result.text===word&&result.offset===word.length,`Native typing preserves ${word} and its advancing caret`);
}
let result=nativeInsert({before:'vrifica',start:1,data:'e'});
check(result.text==='verifica'&&result.offset===2,'Insertion in the middle keeps the suffix and its actual insertion position');
result=nativeInsert({before:'erifica',start:0,data:'v'});
check(result.text==='verifica'&&result.offset===1,'Typing at the beginning advances only past the inserted character');
result=nativeInsert({before:'alpha',start:5,end:1,data:'E'});
check(result.text==='aE'&&result.offset===2,'Backward selection replacement retains the correct range');
result=nativeInsert({before:'veri',start:4,data:'verifică',after:'verifică',targetRange:[0,4]});
check(result.text==='verifică'&&result.offset===8,'An explicit replacement target range supports keyboard word correction');
let priorRanges=ranges;
result=nativeInsert({afterOffset:2});
check(result.text==='ve'&&result.offset===2&&ranges===priorRanges,'A valid native caret is never moved');
result=nativeInsert({composing:true});
check(result.offset===0&&ranges===priorRanges,'An input marked as composing retains ownership of its selection');
gesture('pointerdown',replacement);gesture('compositionstart',replacement);
result=nativeInsert({});
check(result.offset===0&&ranges===priorRanges,'An ongoing composition is respected even if one input omits its flag');
gesture('compositionend',replacement);
for(const [label,args] of [
 ['a settings field',{target:field}],['an untrusted event',{trusted:false}],
 ['a replaced text node',{replaceNode:true}],['an unmatched text mutation',{after:'corrected'}],
 ['a deletion',{inputType:'deleteContentBackward',data:''}],['an empty insertion',{data:''}]
]){
 const beforeRanges=ranges;result=nativeInsert(args);
 check(result.offset===0&&ranges===beforeRanges,`Caret protection leaves ${label} untouched`);
}
nativeInsert({});selection.anchorOffset=selection.focusOffset=0;priorRanges=ranges;
gesture('input',replacement,{inputType:'insertText',data:'e',isComposing:false});
check(selection.anchorOffset===0&&ranges===priorRanges,'A duplicate input cannot replay the previous repair or override later navigation');
console.log(`Ziva mobile DOM/focus (simulated gestures): ${checks} checks, 0 failures`);
