module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class SensorAdapter extends events.EventEmitter

    constructor: (device, client, pimaticId) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      @pimaticId = pimaticId
      @discoveryId = pimaticId
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
      env.logger.debug "handlemessage sensor -> No action"
      return

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/sensor/' + @device.id + 'T/config'
        env.logger.debug "Discovery cleared _topic: " + _topic 
        @client.publish(_topic, null, ()=>
          _topic = @discoveryId + '/sensor/' + @device.id + 'H/config'
          env.logger.debug "Discovery cleared _topic: " + _topic 
          @client.publish(_topic, null, ()=>
            resolve()
          )
        )
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _configTemp = 
          name: "Temperature " + @device.id
          state_topic: @pimaticId + '/sensor/' + @device.id + "/state"
          unit_of_measurement: "°C"
          value_template: "{{ value_json.temperature}}"
          device_class: "temperature"
        _topic = @discoveryId + '/sensor/' + @device.id + 'T/config'
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
          name: "Humidity " + @device.id
          state_topic: @pimaticId + '/sensor/' + @device.id + "/state"
          unit_of_measurement: "%"
          value_template: "{{ value_json.humidity}}"
          device_class: "humidity"
        _topic2 = @discoveryId + '/sensor/' + @device.id + 'H/config'
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
          _topic = @pimaticId + '/sensor/' + @device.id + "/state"
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
      @device.removeListener 'temperature', @temperatureHandler
      @device.removeListener 'humidity', @humidityHandler
