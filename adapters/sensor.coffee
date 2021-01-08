module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class SensorAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id
      @hassDeviceIdT = @hassDeviceId + "T"
      @hassDeviceIdH = @hassDeviceId + "H"
      ###
      @_init = true
      @_temperature = 0
      @_humidity = 0
      @device.getTemperature()
      .then((temp)=>
        @_temperature = temp
      ).catch((err) =>
        env.logger.info "Error getTemperature: " + err
      )
      @device.getHumidity()
      .then((hum)=>
        @_humidity = hum
      ).catch((err) =>
        env.logger.info "Error getTemperature: " + err
      )
      ###

      @temperatureHandler = (temp) =>
        env.logger.debug "Temperature change: " + temp
        #if @_temperature isnt temp
        #  @_temperature = temp
        @publishState()
      @device.on 'temperature', @temperatureHandler

      @humidityHandler = (hum) =>
        env.logger.debug "Humidity change: " + hum
        #if @_humidity isnt hum
        #  @_humidity = hum
        @publishState()
      @device.on 'humidity', @humidityHandler

    handleMessage: (packet) =>
      #env.logger.debug "handlemessage sensor -> No action"
      return

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        _hassDeviceIdT = @hassDeviceId + "T"
        _hassDeviceIdH = @hassDeviceId + "H"
        _topic = @discoveryId + '/sensor/' + _hassDeviceIdT + '/config'
        env.logger.debug "Discovery cleared _topic: " + _topic 
        @client.publish(_topic, null, ()=>
          _topic = @discoveryId + '/sensor/' + _hassDeviceIdH + 'H/config'
          env.logger.debug "Discovery cleared _topic: " + _topic 
          @client.publish(_topic, null, ()=>
            resolve()
          )
        )
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _configTemp = 
          name: @hassDeviceIdT
          unique_id: @hassDeviceIdT
          state_topic: @discoveryId + '/sensor/' + @hassDeviceIdT + "/state"
          unit_of_measurement: "°C"
          value_template: "{{ value_json.temperature}}"
          device_class: "temperature"
        _topic = @discoveryId + '/sensor/' + @hassDeviceIdT + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_configTemp)
        _options =
          qos : 1
        @client.publish(_topic, JSON.stringify(_configTemp), _options, (err) =>
          if err
            env.logger.error "Error publishing Discovery Temperature  " + err
            reject()
        )
        _configHum = 
          name: @hassDeviceIdH
          unique_id: @hassDeviceIdH
          state_topic: @discoveryId + '/sensor/' + @hassDeviceIdH + "/state"
          unit_of_measurement: "%"
          value_template: "{{ value_json.humidity}}"
          device_class: "humidity"
        _topic2 = @discoveryId + '/sensor/' + @hassDeviceIdH + '/config'
        env.logger.debug "Publish discover _topic2: " + _topic2 
        env.logger.debug "Publish discover _config2: " + JSON.stringify(_configHum)
        _options =
          qos : 1
        @client.publish(_topic2, JSON.stringify(_configHum), _options, (err) =>
          if err
            env.logger.error "Error publishing Discovery Humidity " + err
            reject()
          resolve()
        )
      )

    publishState: () =>
      @device.getTemperature()
      .then((temp)=>
        @_temperature = temp
        @device.getHumidity()
        .then((hum)=>
          @_humidity = hum
          _topic = @discoveryId + '/sensor/' + @hassDeviceId + "/state"
          _payload =
            temperature: @_temperature
            humidity: @_humidity
          env.logger.debug "_stateTopic: " + _topic + ",  payload: " +  JSON.stringify(_payload)
          _options =
            qos : 1
          @client.publish(_topic, JSON.stringify(_payload), _options)
        ).catch((err) =>
          env.logger.info "Error getting Humidity: " + err
        )
      ).catch((err) =>
        env.logger.info "Error getting Temperature: " + err
      )

    update: () ->
      env.logger.debug "Update not implemented"

    clearAndDestroy: ->
      @clearDiscovery()
      .then () =>
        @destroy()

    destroy: ->
      return new Promise((resolve,reject) =>
        @device.removeListener 'temperature', @temperatureHandler
        @device.removeListener 'humidity', @humidityHandler
        resolve()
      )
