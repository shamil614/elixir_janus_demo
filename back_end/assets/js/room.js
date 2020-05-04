// NOTE: The contents of this file will only be executed if
// you uncomment its entry in "assets/js/app.js".

// To use Phoenix channels, the first step is to import Socket,
// and connect at the socket path in "lib/web/endpoint.ex".
//
// Pass the token on params as below. Or remove it
// from the params if you are not using authentication.
'use strict';

import {
    Socket,
    Presence
} from "phoenix";

let presences = {};
let socket = new Socket("/socket", {
    params: {
        token: window.userToken
    }
});

socket.connect();

// Now that you are connected, you can join channels with a topic:
let channelRoomId = window.channelRoomId;
let channelCurrentUserId = window.currentUserId;

if (channelRoomId) {
  let channel = socket.channel(`room:${channelRoomId}`, {});

  channel.join()
      .receive("ok", resp => {
          // console.log("Joined successfully", resp);
      })
      .receive("error", resp => {
          // console.log("Unable to join", resp);
      });

  channel.on(`room:${channelRoomId}:new_message`, (message) => {
      // console.log("message", message);
      renderMessage(message);
  });

  channel.on("presence_state", state => {
      // console.log("Presence State called");
      presences = Presence.syncState(presences, state);
      renderOnlineUsers(presences);
  });

  channel.on("presence_diff", diff => {
      // console.log("Presence Diff called");
      presences = Presence.syncDiff(presences, diff);
      renderOnlineUsers(presences);
  });

  document.querySelector("#new-message").addEventListener('submit', (e) => {
      e.preventDefault();
      let messageInput = e.target.querySelector('#message-content');

      channel.push('message:add', {
          message: messageInput.value
      });

      messageInput.value = "";
  });
}

const renderMessage = function(message) {
    let messageTemplate = `
    <li class="list-group-item">
      <strong>${message.user.username}</strong>:
      ${message.content}</li>
  `;
    document.querySelector("#messages").innerHTML += messageTemplate;
};

const renderOnlineUsers = function(presences) {
    let onlineUsers = Presence.list(presences, (_id, {
        metas: [user, ...rest]
    }) => {
        return onlineUserTemplate(user);
    }).join("");

    document.querySelector("#online-users").innerHTML = onlineUsers;
};

const onlineUserTemplate = function(user) {
    return `
    <div id="online-user-${user.user_id}">
      <strong class="text-secondary">${user.username}</strong>
    </div>
  `;
};
