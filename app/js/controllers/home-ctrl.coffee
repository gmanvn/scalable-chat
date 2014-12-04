app = angular.module 'scalable-chat'
app.controller 'HomeCtrl', class HomeCtrl

  constructor: ($scope, $state, chat)->
    $scope.usernames = [
      'user-0001'
      'user-0002'
      'user-0003'
      'user-0004'

      '+841265752223'
      '+84906591398'
    ]

    $scope.setUsername = (username)->
#      username = $scope.submitingUsername
#      $scope.submitingUsername = ''
      chat.setUsername username
      $state.transitionTo('list')


    username = chat.getUsername()

    $state.transitionTo('list') if username

