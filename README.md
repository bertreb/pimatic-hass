# pimatic-hass
Pimatic plugin for making Pimatic devices available in Home Assistant

This plugin is using the mqtt discovery function of Home Assistant (Hass) to automaticaly add pimatic devices.
For actionable devices like switch or light the Pimatic devices are synced with Home Assistant. When you change is value in Pimatic or in Home Assitant the states are synced. For readonly devices the values are only exposed readable towards Home Assistant. 

The communication between Pimatic and Hass is done via mqtt. You need to use a mqtt server that is preferably on your local netwerk.

### Preparing Home Assistant
The whole setup of Home Assistant is out of scope of this plugin. So the starting point is a working Hass system with configurator installed/enabled.
In the configurator you open the file "configurations.yaml" and add the following lines.

```
mqtt:
  broker: <broker ip address
  username: <broker username>
  password: <broker password>
  port: <broker port
  discovery: true
  discovery_prefix: hass

```
It's important to use 'hass' as the discovery_prefix, otherwise the automatic installation of devices will not work.

Than you add the MQTT integration in Home Assistant.
Goto to the settings menu and select integrations. Pusg the add button (+) and type mqtt. 
The MQTT integration will showup and you can select and install it.
Fill in the MQTT server parameters from your mqtt server. Save and exit.

The preparation of Home assitant is done! 

### Preparing Pimatic
Install the Hass plugin.In the plugin you configure the ip address, port, username and password of the mqtt server.
If you want you can enable the debug option and read in the logfile log message screen extra debug info.
After succeful installion and configuration of the Hass plugin you can add a Hass device.

### Configuring the HASS device

In the Hass device you can add Pimatic devices by there pimatic-id. No further configuration is needed.
Aftr saving the device config, the connection to Home Assistant is established and per pimati device that you added in the device config a compatible device is created in Home Assistant.

The device type of a Pimatic device determines the Home assistant Device type that is created in Home Assistant device.

Currently the following pimatic devices are supported.

|Pimatic  |direction| Hass     | states            |
|---------|---------|----------|-------------------|
|Switch   |   <->   | Switch   | state             |
|Presence |    ->   | Motion   | presence          |
|Light    |   <->   | Light    | state, brightness |
|Contact  |    ->   | Binary   | state             |
|Temp/hum |    ->   | Binary   | temp, humidity    |

### Adding Pimatic devices in the Hass Gui
In Home Assistant the automatic created Pimatic devices can be added via the 'configure UI' option. 
Via the add button (+) you can select a device type and search on device name. 
The Hass device name is \<hass device type\>.\<pimatic id\>


---
The plugin is Node v10 compatible and in development. You could backup Pimatic before you are using this plugin!
