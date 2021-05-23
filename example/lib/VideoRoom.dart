import 'package:flutter/material.dart';
import 'package:janus_client/janus_client.dart';
import 'package:janus_client/utils.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:janus_client/Plugin.dart';

import 'dart:async';

class VideoRoom extends StatefulWidget {
  @override
  _VideoRoomState createState() => _VideoRoomState();
}

class _VideoRoomState extends State<VideoRoom> {
  JanusClient j;
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  Plugin pluginHandle;
  Plugin subscriberHandle;
  MediaStream remoteStream;
  MediaStream myStream;

  @override
  void didChangeDependencies() async {
    // TODO: implement didChangeDependencies
    super.didChangeDependencies();
  }

  @override
  void initState() {
    super.initState();
    initRenderers();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _newRemoteFeed(JanusClient j, feed) async {
    debugPrint('remote plugin attached');
    j.attach(Plugin(
        plugin: 'janus.plugin.videoroom',
        onMessage: (msg, jsep) async {
          debugPrint('onMessage: ' + msg.toString());
          if (jsep != null) {
            await subscriberHandle.handleRemoteJsep(jsep);
            var body = {
              "request": "start",
              "room": 1234,
              "display": 'dartapp'
            };

            debugPrint('handleRemoteJsep done');

            await subscriberHandle.send(
              message: body,
              jsep: await subscriberHandle.createAnswer(),
            );
            debugPrint('subscriberHandle done');
          }
        },
        onSuccess: (plugin) {
          debugPrint('onSuccess');

          setState(() {
            subscriberHandle = plugin;
          });
          var register = {
            "request": "join",
            "room": 1234,
            "ptype": "subscriber",
            "feed": feed,
            "display": 'dartapp'
//            "private_id": 12535
          };
          debugPrint('subscriberHandle.send register');
          subscriberHandle.send(message: register);
          debugPrint('subscriberHandle.send register done');
        },
        onRemoteStream: (stream) {
          debugPrint('got remote stream: ' + stream.toString());
          setState(() {
            remoteStream = stream;
            _remoteRenderer.srcObject = remoteStream;
          });
        }));
  }

  Future<void> initPlatformState() async {
    setState(() {
      j = JanusClient(iceServers: [
        RTCIceServer(
            url: "stun:stun1.l.google.com:19302",
            username: "",
            credential: ""),
      ], server: [
      	 'http://gophor.me:8088/janus',
      ], withCredentials: false);
      j.connect(onSuccess: (sessionId) async {
        debugPrint('voila! connection established with session id as' +
            sessionId.toString());
        Map<String, dynamic> configuration = {
          "iceServers": j.iceServers.map((e) => e.toMap()).toList()
        };

        debugPrint('Post ICE!');

        j.attach(Plugin(
            plugin: 'janus.plugin.videoroom',
            onMessage: (msg, jsep) async {
              debugPrint('publisheronmsg');
              if (msg["publishers"] != null) {
                var list = msg["publishers"];
                debugPrint('got publishers: ' + list.toString());
                _newRemoteFeed(j, list[0]["id"]);
                debugPrint('_newRemoteFeed');
              }

              if (jsep != null) {
                pluginHandle.handleRemoteJsep(jsep);
              }
            },
            onData: (d) {
              debugPrint('initPlatformState::msg from datachannel: ' + d.text.toString());
            },
            onDataOpen: (d) async {
              debugPrint('initPlatformState::data state changed: ' + d.toString());
            },
            onSuccess: (plugin) async {
              debugPrint('[2] onSuccess');
              setState(() {
                pluginHandle = plugin;
              });
              debugPrint('await initializeMediaDevices');
              MediaStream stream = await plugin.initializeMediaDevices();
              debugPrint('await initializeMediaDevices done');
              setState(() {
                myStream = stream;
              });
              setState(() {
                _localRenderer.srcObject = myStream;
              });

              // Needs to be up here for the datachannel to get set up properly
              debugPrint('initPlatformState::initDataChannel');
              await plugin.initDataChannel();
              debugPrint('initPlatformState::initDataChannel done');

              var register = {
                "request": "join",
                "room": 1234,
                "ptype": "publisher",
                "display": 'dartapp'
              };
              debugPrint('await register');
              await plugin.send(message: register);
              debugPrint('await register done');
              var publish = {
                "request": "configure",
                "audio": true,
                "video": true,
                "data": true,
                "bitrate": 2000000,
                "display": 'dartapp'
              };
              debugPrint('await createOffer');
              RTCSessionDescription offer = await plugin.createOffer();
              debugPrint('await createOffer done');
              await plugin.send(message: publish, jsep: offer);
              debugPrint('await publish done');

            }));
      }, onError: (e) {
        debugPrint('some error occurred');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
              icon: Icon(
                Icons.call,
                color: Colors.greenAccent,
              ),
              onPressed: () async {
                await this.initRenderers();
                await this.initPlatformState();
              }),
          IconButton(
              icon: Icon(
                Icons.call_end,
                color: Colors.red,
              ),
              onPressed: () {
                j.destroy();
                pluginHandle.hangup();
                subscriberHandle.hangup();
                _localRenderer.srcObject = null;
                _localRenderer.dispose();
                _remoteRenderer.srcObject = null;
                _remoteRenderer.dispose();
                setState(() {
                  pluginHandle = null;
                  subscriberHandle = null;
                });
              }),
          IconButton(
              icon: Icon(
                Icons.switch_camera,
                color: Colors.white,
              ),
              onPressed: () {
                if (pluginHandle != null) {
                  pluginHandle.switchCamera();
                }
              }),
          IconButton(
              icon: Icon(
                Icons.arrow_left_rounded,
                color: Colors.white,
              ),
              onPressed: () {
                if (pluginHandle != null) {
                  pluginHandle.sendData(message: stringify("Left"));
                }
              }),
          IconButton(
              icon: Icon(
                Icons.arrow_right_rounded,
                color: Colors.white,
              ),
              onPressed: () {
                if (pluginHandle != null) {
                  pluginHandle.sendData(message: stringify("Right"));
                }
              }),
          ],
        title: const Text('janus_client'),
      ),
      body: Stack(children: [
        Positioned.fill(
          child: RTCVideoView(
            _remoteRenderer,
          ),
        ),
        Align(
          child: Container(
            child: RTCVideoView(
              _localRenderer,
            ),
            height: 200,
            width: 200,
          ),
          alignment: Alignment.bottomRight,
        )
      ]),
    );
  }
}
