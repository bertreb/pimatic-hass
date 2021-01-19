module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  events = require 'events'
  _ = env.require('lodash')

  class BaseMultiSensor extends events.EventEmitter

    pressures = ['hpa','mbar',"pressure"]
    watts = ["w","kw","mw","watt","power"]
    energies = ['kwh','wh','mwh',"watt"]
    luminances = ["lx","lm","luminace"]
    amperes = ["a","ma","ampere", "ka","current"]
    volts = ["v", "mv", "kv", "volt","voltage"]
    temperatures = ["°c","°f","celsius","fahrenheit","temperature"]
    humidities = ["hum","humidity"]
    signals = ["wifi","db","dbm"]
    batteries = ["batt","battery"]
    timestamps = ["date","time","timestamp"]
    motions = ["motion","presence"]

    constructor: () ->

    getDeviceClass: (_attribute, _unit, _label, _acronym)=>

      if !_unit and !_label and !_acronym and !_attribute then return null

      fields = []
      if _attribute? then fields.push _attribute.toLowerCase()
      if _unit? then fields.push _unit.toLowerCase()
      if _label? then fields.push _label.toLowerCase()
      if _acronym? then fields.push _acronym.toLowerCase()

      if _.find(fields,(f)=> f in temperatures)
        @device_class = "temperature"
      else if _.find(fields,(f)=> f in humidities)
        @device_class = "humidity"
      else if _.find(fields,(f)=> f in pressures) 
        @device_class = "pressure"
      else if _.find(fields,(f)=> f in motions) 
        @device_class = "presence"
      else if _.find(fields,(f)=> f in energies)
        @device_class = "energy"
      else if _.find(fields,(f)=> f in amperes)
        @device_class = "current"
      else if _.find(fields,(f)=> f in volts)
        @device_class = "voltage"
      else if _.find(fields,(f)=> f in watts)
        @device_class = "power"
      else if _.find(fields,(f)=> f in luminances)
        @device_class = "illuminance"
      else if _.find(fields,(f)=> f in signals)
        @device_class = "signal_strength"
      else if _.find(fields,(f)=> f in batteries)
        @device_class = "battery"
      else if _.find(fields,(f)=> f in timestamps)
        @device_class = "timestamp"
      else
        @device_class = null
      env.logger.debug "Base getDeviceClass: " + _unit + ", class: " + @device_class
      return @device_class

  return BaseMultiSensor
