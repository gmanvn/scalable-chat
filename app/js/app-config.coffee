app = angular.module 'scalable-chat', [
  'ui.router'
  'btford.socket-io'
]

app.config ($stateProvider, $urlRouterProvider)->
  $urlRouterProvider.otherwise('/home')

  $stateProvider.state('home', {
    url: '/home'
    views: {
      main: {
        templateUrl: 'partials/home.html'
        controller: 'HomeCtrl as home'
      }
    }
  })

  $stateProvider.state('list', {
    url: '/list'
    views: {
      main: {
        templateUrl: 'partials/list.html'
        controller: 'ListCtrl as list'
      }
    }
  })

  $stateProvider.state('list.conversation', {
    url: '/conversation/:id'
    views: {
      conversations: {
        templateUrl: 'partials/conversation.html'
        controller: 'ConversationCtrl'
      }
    }
  })
