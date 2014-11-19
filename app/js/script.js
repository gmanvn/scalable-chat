/**
 * Created by siliconprime on 11/19/14.
 */

var socket = io();

$('form').submit(function(){
  socket.emit('chat message', $('#m').val());
  $('#m').val('');
  return false;
});

socket.on('chat message', function(msg){
  $('#messages').append($('<li>').text(msg));
});

socket.on('new user', function (user) {
  $('#messages').append($('<li>').text('new user has entered the room'));
});

socket.on('user leave', function () {
  $('#messages').append($('<li>').text('A user has left the room'));
});