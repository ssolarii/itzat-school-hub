export function captureChatScroll(root) {
  const history=root.querySelector('[data-community-messages]');
  if(!history)return null;
  return {
    roomId:history.dataset.roomId,
    top:history.scrollTop,
    atEnd:history.scrollHeight-history.scrollTop-history.clientHeight<100,
  };
}

export function restoreChatScroll(root,previous,roomId) {
  const history=root.querySelector('[data-community-messages]');
  if(!history)return;
  history.dataset.roomId=roomId||'';
  history.scrollTop=!previous||previous.roomId!==history.dataset.roomId||previous.atEnd
    ?history.scrollHeight:previous.top;
}
