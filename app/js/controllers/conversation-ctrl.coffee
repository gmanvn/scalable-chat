app = angular.module 'scalable-chat'
app.controller 'ConversationCtrl', class ConversationCtrl

  constructor: ($scope, $stateParams, @chat)->
    id = $scope.id = $stateParams.id

    $scope.conv = @chat.getConversation id

    $scope.sendMessage = ()->
      message = $scope.message
      $scope.message = ''

      chat.sendMessage message, id