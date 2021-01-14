module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'

  class AlarmAdapter extends events.EventEmitter

    constructor: (device, client, discovery_prefix, device_prefix) ->

      @name = device.name
      @id = device.id
      @device = device
      @client = client
      #@pimaticId = pimaticId
      @discoveryId = discovery_prefix
      @hassDeviceId = device_prefix + "_" + device.id
      @device_prefix = device_prefix
      @hassDeviceFriendlyName = device_prefix + ": " + device.id

      @code = @device._pin ? "0000"

      @alarmStates =
        disarmed: "disarmed"
        armed_home: "armed_home"
        armed_away: "armed_away"
        armed_night: "armed_night"
        armed_custom_bypass: "armed_custom_bypass"
        pending: "pending"
        triggered: "triggered"
        arming: "arming"
        disarming: "disarming"

      @device.getState()
      .then (state)=>
        @_state = state
 
      @stateHandler = (state) =>
        env.logger.debug "Alarm state change: " + state
        switch state
          when "disarmed"
            @_state = "disarmed"
          when "armedhome"
            @_state = "armed_home"
          when "armedaway"
            @_state = "armed_away"
          when "armednight"
            @_state = "armed_night"
        @publishState()

      @statusHandler = (status) =>
        env.logger.debug "Alarm status change: " + status
        switch status
          when "pending"
            @_state = "pending"
          when "arming"
            @_state = "arming"
          when "disarming"
            @_state = "disarming"
          when "triggered"
            @_state = "triggered"
          else
            env.logger.debug "Status '#{status}' not relevant"
        @publishState()

      @device.on 'state', @stateHandler
      @device.on 'status', @statusHandler

    handleMessage: (packet) =>
      _items = (packet.topic).split('/')
      #_command = _items[1]
      _value = packet.payload

      env.logger.debug "AlarmPanel message received: " + _value
      
      switch (String _value).toLowerCase()
        when "disarm"
          #@_state = "disarm"
          @device.changeArmTo("disarmed")
        when "arm_away"
          @_state = "arm_away"
          @device.changeArmTo("armedaway")
        when "arm_home"
          @_state = "arm_home"
          @device.changeArmTo("armedhome")
        when "arm_night"
          @_state = "arm_night"
          @device.changeArmTo("armednight")

    clearDiscovery: () =>
      return new Promise((resolve,reject) =>
        _topic = @discoveryId + '/switch/' + @hassDeviceId + '/config'
        env.logger.debug "Discovery cleared _topic: " + _topic 
        @client.publish(_topic, null, (err)=>
          if err
            env.logger.error "Error publishing Discovery " + err
            reject()
          resolve(@id)
        )
      )

    publishDiscovery: () =>
      return new Promise((resolve,reject) =>
        _config = 
          name: @hassDeviceFriendlyName #@hassDeviceId
          unique_id: @hassDeviceId
          cmd_t: @discoveryId + '/' + @hassDeviceId + '/set'
          stat_t: @discoveryId + '/' + @hassDeviceId
          code: @code
          code_arm_required: false
          code_disarm_required: true
          availability_topic: @discoveryId + '/' + @hassDeviceId + '/status'
          payload_available: "online"
          payload_not_available: "offline"

        _topic = @discoveryId + '/alarm_control_panel/' + @hassDeviceId + '/config'
        env.logger.debug "Publish discover _topic: " + _topic 
        env.logger.debug "Publish discover _config: " + JSON.stringify(_config)
        _options =
          qos : 1
        @client.publish(_topic, JSON.stringify(_config), (err) =>
          if err
            env.logger.error "Error publishing Discovery " + err
            reject()
          @device.changeSyncedTo(on)
          resolve(@id)
        )
      )

    publishState: () =>
      #if @_state then _state = "armed_away" else _state = "disarmed"
      _state = @_state
      _topic = @discoveryId + '/' + @hassDeviceId
      _options =
        qos : 0
      env.logger.debug "Publish alarmpanel: " + _topic + ", _state: " + _state
      @client.publish(_topic, String _state) #, _options)

    update: () ->
      env.logger.debug "Update alarm not implemented"

    clearAndDestroy: () =>
      return new Promise((resolve,reject) =>
        @clearDiscovery()
        .then ()=>
          return @destroy()
        .then ()=>
          resolve()
        .catch (err) =>
          env.logger.debug "Error clear and destroy alarm"
      )

    setStatus: (online) =>
      if online then _status = "online" else _status = "offline"
      _topic = @discoveryId + '/' + @hassDeviceId + "/status"
      _options =
        qos : 0
      env.logger.debug "Publish status: " + _topic + ", _status: " + _status
      @client.publish(_topic, String _status) #, _options)


    destroy: ->
      return new Promise((resolve,reject) =>
        @device.removeListener 'state', @stateHandler if @stateHandler?
        @device.removeListener 'status', @statusHandler if @statusHandler?
        resolve()
      )
