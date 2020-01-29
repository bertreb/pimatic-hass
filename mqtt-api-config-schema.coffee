module.exports = {
  title: "Plugin config options"
  type: "object"
  properties:
    mqttServer:
      description: "The ip adress of the mqtt server"
      type: "string"
      required: true
    mqttUsername:
      description: "The username for the mqtt server"
      type: "string"
      default: "pimatic"
    mqttPassword:
      description: "The password for the mqtt server"
      type: "string"
    mqttPort:
      description: "The portnumber of the mqtt api"
      type: "number"
      default: 1883
    hassTopic:
      description: "The discovery topic for hass"
      type: "string"
      default: "pimatic"
    debug:
      description: "Debug mode. Writes debug messages to the pimatic log, if set to true."
      type: "boolean"
      default: false

}
