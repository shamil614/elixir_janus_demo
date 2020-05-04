'use strict';

import {
  Socket
} from "phoenix";
import adapter from 'webrtc-adapter';

// send the user token to phx for authentication
let socket = new Socket("/socket", {
  params: {
    token: window.userToken
  }
});

// room and user info
let channelRoomId = window.channelRoomId;
let channelCurrentUserId = window.currentUserId;

var localVideo = document.getElementById('localVideo');
var remoteVideoWrapper = document.getElementById('remoteVideoWrapper');
var publisherHandle = null;
var publisherPc = null;
var call = {
  private_id: null,
  remote_feeds: [{}]
};
var randomRef = getRandomInt(0, 1000000);

window.publisherPc = publisherPc;

// setup location for storing and tracking handles that are subscribing to remote feeds
window.subscribedHandles = [];

// helpful to disable audio connections for development / testing
var globallyDisableAudio = true;

class Handle {
  constructor({
    id,
    peerConnection,
    ptype
  }) {
    var handle = this;
    let negotiating = false;

    this.id = id;
    this.peerConnection = peerConnection;
    // should be either publisher or subscriber
    this.ptype = ptype;

    // setup some default functions for the RTCPeerConnection
    this.peerConnection.onicecandidate = ({
      candidate
    }) => {
      const handleId = this.id;

      console.log("**** Received Ice Candidate ****");
      console.log(candidate);

      if (candidate != null) {
        const sanitizedCandidate = {
          "candidate": candidate.candidate,
          "sdpMid": candidate.sdpMid,
          "sdpMLineIndex": candidate.sdpMLineIndex
        };
        callChannel.push("trickle", {
          handle_id: handleId,
          candidate: sanitizedCandidate
        });
      } else {
        console.log("All ICE Candidates sent");
        const completed = {
          handle_id: handleId,
          "candidate": {
            "completed": true
          }
        };
        callChannel.push("trickle", completed);
      }
      logConnectionState(this.peerConnection, "Trickle");
    };

    this.peerConnection.ontrack = (event) => {
      console.log("Handle PeerConnection received ontrack event");
      console.log(`Ontrack Handle Type ${this.ptype}`);

      let existingVideo = document.getElementById(this.id);
      if (this.ptype == "subscriber" && existingVideo === null) {
        console.log("Adding Remote Video");
        const remoteVideo = document.createElement("video");

        remoteVideo.setAttribute("id", this.id);
        remoteVideo.setAttribute("autoplay", "");
        remoteVideo.setAttribute("playsinline", "");
        remoteVideo.srcObject = event.streams[0];

        remoteVideoWrapper.appendChild(remoteVideo);
      }
    };

    this.peerConnection.onnegotiationneeded = async () => {
      let pc = this.peerConnection;
      console.log("********* Attempting Negotiation *********");
      console.log(`Negotiating: ${negotiating}`);
      console.log(`Signaling State: ${pc.signalingState}`);

      try {
        if (negotiating || pc.signalingState != "stable") return;
        negotiating = true;
        await sendOffer(this);
      } catch (err) {
        console.error(err);
      } finally {
        negotiating = false;
      }
    };
  } // end of constructor

  // Media constraints for building an Answer for a remote feed
  static receiveMediaConstraints() {
    let mediaConstraints = {};
    if (adapter.browserDetails.browser == "firefox" || adapter.browserDetails.browser == "edge") {
      mediaConstraints = {
        offerToReceiveAudio: maybeDisableAudio(true),
        offerToReceiveVideo: true
      };
    } else {
      mediaConstraints = {
        mandatory: {
          OfferToReceiveAudio: maybeDisableAudio(true),
          OfferToReceiveVideo: true
        }
      };
    }
  }
};

const constraints = {
  audio: maybeDisableAudio(true),
  video: true
};

const pc_constraints = {
  "optional": [{
    "DtlsSrtpKeyAgreement": true
  }]
};

if (channelRoomId) {
  socket.connect();
  var callChannel = socket.channel(`room_call:${randomRef}:room-${channelRoomId}:user-${currentUserId}`, {
    room_id: channelRoomId,
    user_id: currentUserId
  });

  // join the phx channel
  callChannel.join()
    .receive("ok", resp => {
      console.log("Join Event Received");
    });


  callChannel.on("handle_created", ({
    handle_id,
    ice_servers,
    ptype
  }) => {
    console.log(`Handle Created => ${handle_id} | ${ptype}`);
    if (ptype === "publisher") {
      console.log("IceServers Received");
      console.log(ice_servers);

      // create the Handle for the PeerConnection
      publisherPc = new RTCPeerConnection({
        iceServers: ice_servers,
        iceTransportPolicy: "relay"
      }, pc_constraints);
      publisherHandle = new Handle({
        id: handle_id,
        peerConnection: publisherPc,
        ptype: ptype
      });

    } else {
      console.log("Sever sent a subscriber handle");
    }
  });

  // joined the video room
  callChannel.on("joined", async ({
    private_id,
    handle
  }) => {
    console.log(`${handle.ptype} Handle ${handle.id} joined room`);

    // request UserMedia, streams, etc
    start(publisherHandle);
  });

  callChannel.on("trickle_completed", async () => {
    console.log("Server Messaged => Trickle Completed");
  });

  callChannel.on("answer", async ({
    jsep,
    handle
  }) => {
    verify_handle(handle, publisherHandle);
    let pc = publisherHandle.peerConnection;

    console.log("******** Received Answer from Server ********");
    console.log(jsep);
    await pc.setRemoteDescription(jsep).catch((error) => {
      console.log("Remote Description ERROR !!!!!!!!!!!");
      console.log(error);
    });
  });

  // incoming offer for published remote stream
  // first time we get a handle_id for the remote stream
  callChannel.on("offer", async ({
    handle,
    ice_servers,
    jsep
  }) => {
    console.log("Remote Offer received *****");
    console.log(jsep);
    console.log(`Subscribed Handle ID ${handle.id}`);
    console.log("IceServers Received ===>");
    console.log(ice_servers);

    if (handle.ptype != "subscriber") {
      throw "Wrong handle type"
    }

    let pc = new RTCPeerConnection({
      iceServers: ice_servers,
      iceTransportPolicy: "relay"
    }, pc_constraints);
    let subscriberHandle = new Handle({
      id: handle.id,
      peerConnection: pc,
      ptype: "subscriber"
    });
    await pc.setRemoteDescription(jsep).catch((error) => {
      console.log("Error on published feed remote description");
      console.log(error);
    });

    const constraints = Handle.receiveMediaConstraints();
    const answer = await pc.createAnswer(constraints);
    pc.setLocalDescription(answer).catch((error) => {
      console.log("Error on published feed local description");
      console.log(error);
    });

    // send answer jsep to Janus
    callChannel.push("start", {
      handle_id: subscriberHandle.id,
      jsep: answer
    });

    window.subscribedHandles.push(handle);
  });
}

// call flow
function attachedMediaStream(video, stream) {
  video.srcObject = stream;
  video.play();
}

async function requestUserMedia(constraints) {
  try {
    const stream = await navigator.mediaDevices.getUserMedia(constraints);
    window.stream = stream;
    console.log("Local Stream");
    console.log(stream);
    return stream;
  } catch (e) {
    console.error(e);
  }
};

async function start(handle) {
  let pc = handle.peerConnection;

  console.log("******** Starting call by requesting user media *******");
  try {
    // get local stream, show it in self-view and add it to be sent
    const stream = await requestUserMedia(constraints);
    const videoTracks = stream.getTracks();

    videoTracks.forEach((track) => {
      console.log(track);
      pc.addTrack(track, stream);
    });
    console.log(`Using video device: ${videoTracks[0].label}`);
    window.localStream = stream; // make variable available to browser console

    attachedMediaStream(localVideo, stream);
  } catch (err) {
    console.error(err);
  }
}

async function sendOffer(handle) {
  let pc = handle.peerConnection;

  try {
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer).catch((error) => {
      console.log("Local Description ERROR !!!!!!!!!!!");
      console.log(error);
    });

    let jsep = {
      type: offer.type,
      sdp: offer.sdp
    };
    let publish = {
      request: "publish",
      audio: maybeDisableAudio(true),
      data: true,
      video: true
    };
    let offerMessage = {
      handle: {
        id: handle.id,
        ptype: handle.ptype
      },
      jsep: jsep,
      message: publish
    };
    console.log("sending offer @@@@@@@@@@");
    console.log(offerMessage);

    callChannel.push("offer", offerMessage);

    return offer;

  } catch (err) {
    console.error(err);
  }
}

// Helper functions
function getRandomInt(min, max) {
  min = Math.ceil(min);
  max = Math.floor(max);
  return Math.floor(Math.random() * (max - min)) + min; //The maximum is exclusive and the minimum is inclusive
}

function logConnectionState(pc, label) {
  console.log(`${label} => PeerConnection State ${pc.connectionState}`);
}

function maybeDisableAudio(currentValue) {
  if (globallyDisableAudio === true) {
    console.log("********** Audio Disabled **********");
    return false;
  } else {
    return currentValue;
  }
}

function verify_handle({
  id,
  ptype
}, handle) {
  if (id != handle.id && ptype != handle.ptype) {
    throw "Received handle does not match expected handle";
  }
}
