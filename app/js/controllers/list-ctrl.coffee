app = angular.module 'scalable-chat'
app.controller 'ListCtrl', class ListCtrl

  constructor: ($scope, @chat) ->
    $scope.username = chat.getUsername()

    $scope.$watch (-> chat.online), (online) ->
      $scope.online = online


  logout: ()->
    @chat.logOut()
    

  chatWith: (user)->
    @chat.startConversation user