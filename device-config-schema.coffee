module.exports = {
  title: "pimatic-hass device config schemas"  
  HassDevice: {
    title: "pimatic hass"
    description: "Hass device"
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
