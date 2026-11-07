// Functional DOM/focus tests with simulated trusted gestures and editor handlers.
// These tests do not establish rendering or physical Android IME behavior.
import fs from 'node:fs';
import vm from 'node:vm';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {parseHTML}=require(process.env.ZIVA_DOM_MODULE || 'linkedom');
const script=fs.readFileSync(process.env.ZIVA_MOBILE_SCRIPT || 'platform/android/java/editor/src/main/assets/ai/ziva-mobile.js','utf8');
const {window,document,HTMLElement,Element,MutationObserver,Event}=parseHTML(`<!doctype html><html><head></head><body><header><button data-testid="open-settings-button">Settings</button></header><div data-testid="chat-header-panels"><div>Details</div></div><div data-message-scroller-viewport>Messages</div><section><form><div data-slot="input-group-control"><div data-testid="composer-input" contenteditable="true" tabindex="0"><p>Draft</p></div></div><button type="submit" data-testid="composer-send">Send</button></form></section><div id="dialog"><input type="password" id="key"></div></body></html>`);
let active=document.body,now=10000,checks=0,focusCalls=0,blurCalls=0;
const listeners=new Map();
const add=document.addEventListener.bind(document);
document.addEventListener=(name,fn,options)=>{
  if(!listeners.has(name))listeners.set(name,[]);
  listeners.get(name).push({fn,capture:options===true||!!options?.capture});
  add(name,fn,options);
};
Object.defineProperty(document,'activeElement',{get:()=>active});
HTMLElement.prototype.focus=function(){focusCalls++;active=this;this.dispatchEvent(new Event('focusin',{bubbles:true}))};
HTMLElement.prototype.blur=function(){blurCalls++;if(active===this)active=document.body};
let delayedMicrophone=false,resolveMicrophone;
const track=()=>({readyState:'live',stops:0,stop(){this.stops++;this.readyState='ended'},addEventListener(){}});
let microphoneTrack=track();
const mediaDevices={getUserMedia:async()=>{
  if(delayedMicrophone)return new Promise(resolve=>{resolveMicrophone=resolve});
  return {getTracks:()=>[microphoneTrack]};
}};
const originalFocus=HTMLElement.prototype.focus;
const context={window,document,HTMLElement,Element,MutationObserver,DOMException,navigator:{mediaDevices},performance:{now:()=>now},requestAnimationFrame:fn=>setImmediate(fn),queueMicrotask};
vm.runInNewContext(script,context);
const check=(ok,label)=>{if(!ok)throw Error(label);checks++};
// Capture -> official target/React-root handler -> document bubble. The caller
// controls the microtask checkpoint, just as the browser completes dispatch.
const gesture=(name,target,extra={},official=()=>{})=>{
  const event={target,isTrusted:true,...extra};
  const handlers=listeners.get(name)||[];
  handlers.filter(item=>item.capture).forEach(item=>item.fn(event));
  official(event);
  handlers.filter(item=>!item.capture).forEach(item=>item.fn(event));
};
const flush=async()=>{await Promise.resolve()};
const input=document.querySelector('[data-testid="composer-input"]');
const field=document.querySelector('#key');
const send=document.querySelector('[data-testid="composer-send"]');
const form=input.closest('form');
const settings=document.querySelector('[data-testid="open-settings-button"]');
const edit=node=>{gesture('pointerdown',node);node.focus()};
check(document.querySelectorAll('#godot-ziva-mobile-style').length===1,'Installs one host stylesheet');
check(HTMLElement.prototype.focus===originalFocus,'Does not replace the focus primitive');
check(form.hasAttribute('data-godot-ziva-composer'),'Recognizes the official composer');
check(input.closest('section').hasAttribute('data-godot-ziva-composer-region'),'Bounds composer notices separately');
check(document.querySelector('header').hasAttribute('data-godot-ziva-header'),'Recognizes the official header');
input.focus();check(active===document.body&&!window.__godotZivaWantsKeyboard(),'Blocks upstream startup autofocus');
gesture('pointerdown',input.firstElementChild);input.focus();
check(active===input&&window.__godotZivaWantsKeyboard(),'Paragraph tap authorizes editing');
let previousBlur=blurCalls;
gesture('pointerdown',send);
check(active===input&&blurCalls===previousBlur&&window.__godotZivaWantsKeyboard(),'Send pointerdown preserves the focused draft and IME intent');
gesture('click',send,{},()=>check(active===input&&blurCalls===previousBlur,'Official click handler runs before any host blur'));
await flush();check(active===input,'Send click alone cannot dismiss before form submission');
let modelRead=false,officialMicrotask=false;
gesture('submit',form,{},()=>{
  modelRead=active===input&&input.textContent==='Draft';
  queueMicrotask(()=>{officialMicrotask=active===input});
});
check(modelRead&&active===input,'Official submit reads the draft before focus teardown');
await flush();check(officialMicrotask&&active===document.body,'Official microtask runs before deferred host dismissal');
input.focus();check(active===document.body&&!window.__godotZivaWantsKeyboard(),'Completed submission blocks unsolicited refocus');
edit(input);gesture('compositionstart',input);
input.firstElementChild.textContent='pădure';
gesture('submit',form,{},()=>check(active===input&&input.textContent==='pădure','Composition draft reaches the official handler unchanged'));
await flush();check(active===input&&window.__godotZivaWantsKeyboard(),'Submit never tears down an active composition');
gesture('compositionend',input);
check(active===input,'Composition end does not blur during capture');
await flush();check(active===document.body,'Pending dismissal follows composition completion');
edit(input);gesture('submit',form);gesture('pointerdown',input);
await flush();check(active===input&&window.__godotZivaWantsKeyboard(),'A new explicit edit cancels stale scheduled dismissal');
gesture('compositionstart',input);gesture('submit',form);await flush();
gesture('pointerdown',input);gesture('compositionend',input);await flush();
check(active===input,'A new edit cancels a composition-delayed dismissal too');
previousBlur=blurCalls;
gesture('pointerdown',settings);
check(active===input&&blurCalls===previousBlur,'Outside pointerdown does not resize or blur before activation');
gesture('click',settings,{},()=>check(active===input,'Settings activation runs before dismissal'));
await flush();field.focus();check(active===document.body,'Settings cannot autofocus its text field');
edit(field);check(active===field&&window.__godotZivaWantsKeyboard(),'Intentional settings editing works');
window.__godotZivaDismissKeyboard();input.focus();check(active===document.body,'Hiding the tab clears editing intent');
gesture('keydown',document.body,{key:'Tab'});field.focus();check(active===field,'Physical Tab navigation works');
now+=1500;window.__godotZivaDismissKeyboard();input.focus();check(active===document.body,'Tab authorization expires');
const beforeFocus=focusCalls;
gesture('click',input);
check(active===document.body&&focusCalls===beforeFocus,'Accessibility click never synthesizes focus or moves the caret');
input.focus();check(active===input,'Accessibility activation authorizes the official editor focus');
const toggle=document.querySelector('#godot-ziva-panels-toggle');check(!!toggle,'Extra panels retain an accessible control');
toggle.click();check(document.querySelector('[data-testid="chat-header-panels"]').hasAttribute('data-godot-expanded'),'Panel expands');
toggle.click();check(toggle.getAttribute('aria-expanded')==='false','Panel collapses');
vm.runInNewContext(script,context);check(document.querySelectorAll('#godot-ziva-mobile-style').length===1,'Repeated adaptation is idempotent');
const extra=document.createElement('div');extra.innerHTML='<form><div data-testid="composer-input" contenteditable="true"></div></form>';
input.closest('section').remove();document.body.append(extra);
await new Promise(r=>setTimeout(r,40));
check(extra.firstElementChild.hasAttribute('data-godot-ziva-composer'),'Observer adapts the SPA replacement composer');
const oldEditor=extra.querySelector('[contenteditable]');edit(oldEditor);gesture('compositionstart',oldEditor);
const replacement=document.createElement('div');replacement.setAttribute('contenteditable','true');replacement.setAttribute('data-testid','composer-input');replacement.textContent='română';
oldEditor.replaceWith(replacement);replacement.focus();gesture('compositionend',replacement);
check(active===replacement&&replacement.textContent==='română'&&window.__godotZivaWantsKeyboard(),'Replacing the composing DOM node preserves editing intent');
const panels=document.querySelector('[data-testid="chat-header-panels"]');panels.innerHTML='';
await new Promise(r=>setTimeout(r,40));check(!document.querySelector('#godot-ziva-panels-toggle'),'Empty panels remove the toolbar');
await mediaDevices.getUserMedia({audio:true});window.__godotZivaReleaseMicrophone();
check(microphoneTrack.stops===1,'Tab hide releases microphone tracks');
delayedMicrophone=true;microphoneTrack=track();const late=mediaDevices.getUserMedia({audio:true});
window.__godotZivaReleaseMicrophone();resolveMicrophone({getTracks:()=>[microphoneTrack]});
let cancelled=false;try{await late}catch(error){cancelled=error.name==='AbortError'}
check(cancelled&&microphoneTrack.stops===1,'Late microphone acquisition after hide is cancelled');

// The editor/IME supplies the text and selection, including replacement nodes,
// root-node selections, autocorrection and incomplete composing flags. The host
// must never inspect or repair that selection or rewrite the committed text.
let selectionReads=0,ranges=0;
const selection={anchorNode:null,focusNode:null,anchorOffset:0,focusOffset:0,
 get isCollapsed(){return this.anchorNode===this.focusNode&&this.anchorOffset===this.focusOffset},
 removeAllRanges(){throw Error('Host removed editor selection')},addRange(){throw Error('Host replaced editor selection')}};
window.getSelection=()=>{selectionReads++;return selection};
document.createRange=()=>{ranges++;throw Error('Host created a repair range')};
function nativeInput({before='v',start=1,text='ve',offset=2,inputType='insertText',data='e',isComposing=false,target=replacement,replaceNode=false,rootCaret=false,trusted=true}){
 replacement.textContent=before;const node=replacement.firstChild;
 selection.anchorNode=selection.focusNode=rootCaret?replacement:node;
 selection.anchorOffset=selection.focusOffset=start;
 const extra={inputType,data,isComposing,isTrusted:trusted};
 gesture('beforeinput',target,extra);
 if(replaceNode)replacement.textContent=text;else node.nodeValue=text;
 const selected=rootCaret?replacement:replacement.firstChild;
 selection.anchorNode=selection.focusNode=selected;selection.anchorOffset=selection.focusOffset=offset;
 gesture('input',target,extra);
 return replacement.textContent===text&&selection.anchorNode===selected&&selection.focusNode===selected&&selection.anchorOffset===offset&&selection.focusOffset===offset&&selectionReads===0&&ranges===0;
}
for(const [label,args] of [
 ['valid insertion',{}],['zero caret owned by editor',{offset:0}],
 ['root-node caret',{rootCaret:true,start:1,offset:1}],
 ['replaced text node',{replaceNode:true,offset:0}],
 ['autocorrection',{before:'veri',start:4,text:'verifică',data:'verifică',inputType:'insertReplacementText',offset:8}],
 ['composition input',{isComposing:true,inputType:'insertCompositionText',offset:0}],
 ['deletion',{before:'ve',start:2,text:'v',inputType:'deleteContentBackward',data:null,offset:1}],
 ['settings input',{target:field}],['untrusted input',{trusted:false}]
])check(nativeInput(args),`Host preserves editor ownership for ${label}`);
gesture('compositionstart',replacement);
check(nativeInput({offset:0}),'An ongoing composition remains untouched when input omits the composing flag');
gesture('compositionend',replacement);
check(selectionReads===0&&ranges===0,'Host never reads or writes editor selection');
console.log(`Ziva mobile DOM/focus (simulated gestures): ${checks} checks, 0 failures`);
