apn = require 'apn'
filePath = './config/Certificates_DEVELOPMENT_PLUME.p12'


conn = apn.Connection {
  production: false

}