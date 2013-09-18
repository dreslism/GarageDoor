// Sensors are active low 
doorOpen    <- 0;
doorClosed  <- 1;

// Only send this once a day
sentDoorIsOpenMessage <- 0;

// Time of last valid switch event
lastevent <- 0;
// Last processed status
lastDoorState <- -1;

otime <- 0;
//ctime <- 0;

local garageStatusPort  = OutputPort("garageStatusPort","string");
 
/*  
  temperature sensor used is tmp36 from adafruit.com for $2.00
  http://learn.adafruit.com/tmp36-temperature-sensor
  temp range -40°C to 150°C / -40°F to 302°F
*/
local GTemp = OutputPort("GTemp","number");
local reading = null;
local ratio = null;
local voltage = null;
local temperatureC = null;
local temperatureF = null;
local temp = null;
local startState;

function toggleDoor(){
    agent.send("Activated", 0);                
    server.log("Pulse Start");
    hardware.pin7.write(1);
    imp.sleep(0.5);
    hardware.pin7.write(0);
    server.log("Pulse End");
}
function queryDoor(){

    server.log("Door status Query");
                  
    //read the temperature.
    local temp = get_temp();
    //read again as sometimes the temp is off my 5 degrees on wakeup
    imp.sleep(0.5);
    temp = get_temp();
                  
    //read the garage door sensors
    local doorState = hardware.pin8.read();                    
                  
    if (doorState == doorClosed) {
        server.log("[Query] door is closed");
        agent.send("buttonClosedQuery", temp);
    }
    else {
        if (doorState == doorOpen) {
            server.log("[Query] door is open");
            local ctime = time();
            ctime = ctime - otime;            
            server.log("[Query] Current open time = " + ctime);            
            agent.send("buttonOpenQuery", {curTemp=temp, ctime = ctime});                       
        }
    }
}

function get_temp() {
  
  // get the raw voltage value from temp sensor btw 0-65535
  // in this case that needs mapping to the range 0-3.3v
  reading = hardware.pin1.read();
  // get the ratio 
  ratio = 65535.0 / reading;
  
  // make units milivolts and get voltage we can work with
  //voltage = (hardware.voltage() * 1000) / divider;
  voltage = 3300 / ratio;
  
  // get temperature in degrees Celsius
  temperatureC = (voltage - 500) / 10.0;
    
  // convert to degrees Farenheit
  temperatureF = (temperatureC * 9.0 / 5.0) + 32.0;
  
  //server.log("temp: " + temperatureF);
  
  // set our output to desired temperature unit
  temp = temperatureF;
  return temp;   
}

class GaragePort extends InputPort
{
 
    type = "command"
    name = "garageIn"
 
    function set(value) {
        
        // This code checking for values is not needed. Basically every time this funciton is 
        // called, all you need to do is pulse pin 7 which closes the relay and then
        // releases it simulating a button push. I was curious to see how squirrel compares
        // strings....
        if( value ) {
            
            //check if this is the open/close button
            server.log("HTTP: " + value );
            local startIdx = value.find("Open");
            server.log("IDX: " + startIdx );
            if( startIdx != null )
            {
              toggleDoor();
            }
            
            // Check if this is a query button
            if (startIdx == null ) {
              server.log("HTTP: " + value );
              local startIdx = value.find("Query");
              server.log("IDX: " + startIdx );
              
                if ( startIdx != null ) {
                    // Query the door
                    queryDoor();                             
                } // if startIdx != null
            } //if (startIdx == null ) {        
        } // if( value ) { 
    }
}


// use this routine to see if it's past 9:30 at night.
// If it's past 10:00PM (22:00), and the garage door has been open for 10 minutes
// then notify me, or just close it

function pollTimeOfDay(){

  //server.log("[pollTimeOfDay] starting");
  local d = date(time()-(4*60*60));
  
  // clear flag for next day
  if (sentDoorIsOpenMessage && d.hour < 21) {
    sentDoorIsOpenMessage = 0;
    server.log("[pollTimeOfDay] clearing sentDoorIsOpenMessage flag")
  }

  local doorState = hardware.pin8.read();
  // if door is open past 9 PM, and have not sent message, let's see how 
  // long it has been open for, if open for more than 10 minutes, send message.
  if (doorState == doorOpen && d.hour >= 21 && !sentDoorIsOpenMessage) {
    local ctime = time();
    ctime = ctime - otime;         
    if (ctime > 600) {
      sentDoorIsOpenMessage = 1;
      agent.send("pleaseCloseDoor", 0); 
      server.log("[pollTimeOfDay] Door Needs to be closed");
    }
  }

//  server.log("[pollTimeOfDay] hour=" + d.hour);
//  server.log("[pollTimeOfDay] min=" + d.min);
//  server.log("[pollTimeOfDay] day=" + d.day);  
  logTemp();
  imp.wakeup(60, pollTimeOfDay);
}

function logTemp() {
  local temp = get_temp();
  //read again as sometimes the temp is off my 5 degrees on wakeup
  imp.sleep(0.5);
  temp = get_temp();
  server.show(temp);
  GTemp.set(temp);
  agent.send("curTemp", temp);
  //server.log(format("Temp=%0.1fF", temp));
}

function processGDoorInput() {

  local doorState = hardware.pin8.read();
  
  if (doorState != lastDoorState) {
    lastDoorState = doorState;

    server.log("[processGDoorInput] starting");
    server.log("[processGDoorInput] doorState = " + doorState);        
  
    // read temp so we can report it to user in notification
    local temp = get_temp();

    if (doorState == doorClosed) {  
      server.log("[processGDoorInput] door was closed");
      // don't send temp as we write door open time on agent push
      local ctime = time();
      server.log("[processGDoorInput] Unix close time =" + ctime);
      ctime = ctime - otime;
      server.log("Amount of time door was open = " + (ctime) + " seconds");      
      agent.send("buttonClosed", {curTemp=temp, ctime=ctime});                            
    }
    else {
      if (doorState == doorOpen) {    
        server.log("[processGDoorInput] door was opened");
        otime = time();        
        server.log("[processGDoorInput] Unix open time = " + otime);        
        agent.send("buttonOpen", temp);
      }
    }
  }
}

agent.on("siriQuery", function(value) {
  server.log("got siriQuery");
  local ctime = time();
  ctime = ctime - otime;
  local temp = get_temp();
  //read again as sometimes the temp is off my 5 degrees on wakeup
  imp.sleep(0.5);
  temp = get_temp();  
  agent.send("siriData", {curTemp=temp, openTime=ctime, doorOpen = !hardware.pin8.read()});     
});

// agent code to handle json code sent from "Little Devil" iphone app.
agent.on("response",function(value) {
   
   // find key "ButtonQuery"
   if ("ButtonQuery" in value){
        server.log("Got Json Query request");
        // do something cool with value of buttonquery
        /* local x = value.ButtonQuery.tofloat();
          Or
        if (value.ButtonQuery == "0") { */
        
        // Query the door
        queryDoor();       
   }
   // find key "ButtonOpen"  
   if ("ButtonOpen" in value || "ButtonClose" in value){
      server.log("Got Json Open/Close request"); 
      toggleDoor();       
   }
   
});

function pin8Changed() {
  // is this likely a bounce?
//  if ((hardware.millis()-lastevent)>50) {
  if ((hardware.millis()-lastevent)>100) {    
    // new event, process
    lastevent = hardware.millis();

    // read pin, deal with 1 or 0
    processGDoorInput();

    // set timer to call back and get in sync in case this is the last event we see
    imp.wakeup(0.1, processGDoorInput);
  } else {
    // likely a bounce, ignore
  }
}
//******************************************************************
function GetData(){
    return "SomeData";
}

agent.on("GetValue", function(timestamp) {
    local data = GetData();
    agent.send("GetValueResponse", { t = timestamp, d = data});
});
// *******************************8888888888888888888888







imp.configure("Garage Door", [GaragePort], [GTemp]);

// trigger for relay to open/close door
hardware.pin7.configure(DIGITAL_OUT);

// input sensors for door open/close
hardware.pin8.configure(DIGITAL_IN_PULLUP, pin8Changed);
//hardware.pin9.configure(DIGITAL_IN, pin9changed);

/* Temperature sensor to read temperature when queried */
hardware.pin1.configure(ANALOG_IN);


// Make sure pin is low - relay off
hardware.pin7.write(0);

// see if door is open when we start, if it is, take current time as open time
startState = hardware.pin8.read();
if (startState == doorOpen) {    
  server.log("door was open at startup");
  otime = time(); 
  agent.send("doorWasOpen", 1);
}
else {
  server.log("door was closed at startup");
  otime = time(); 
  agent.send("doorWasClosed", 1);  
}
// need to wake up every minute and see if it is 9PM 
imp.wakeup(2, pollTimeOfDay);
