module.exports = {
  title: "pimatic-mqtt-api device config schemas"  
  MqttApiDevice: {
    title: "pimatic mqtt api"
    description: "Mqtt api device"
    type: "object"
    extensions: ["xLink", "xOnLabel", "xOffLabel"]
    properties:
      devices:
        description: "List of devices to be expose to Home Assistant"
        type: "array"
        default: []
        format: "table"
        items:
          description: "exposed device"
          type: "string"
  }
}
