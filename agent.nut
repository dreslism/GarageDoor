local doorOpen = 0;
local curTemp =  0;
local openTime = 0;

// New call response mechanism
//******************************************************
// max round-trip time: agent -> device -> agent
const TIMEOUT = 10.0;

// response queue
HttpResponses <- {};

// Send timeout responses when required
function CleanResponses() {
    // get current time
    local now = time();
    
    // loop through response queue
    foreach(t, resp in HttpResponses) {
        // if request has timed-out
        if (now - t > TIMEOUT) {
            // log it, send the response, then delete it
            server.log("Request " + t + " timed-out");
            resp.send(408, "Request Timed-out");
            delete HttpResponses[t];
        }
    }
    // check for timeouts every seconds
    imp.wakeup(1.0, CleanResponses);
} CleanResponses();

// sends a response based on a timestamp
function SendResponse(t, code, body) {
    // if the response is in our queue (it hasn't timed out)
    if (t in HttpResponses) {
        // send it
        HttpResponses[t].send(code, body);
    } else {
        // if it wasn't in the queue, log a message
        server.log("Response " + t + " not found in response queue");
    }
}


//***********************************************************************

// *************** prowl function **********************
const PROWL_KEY = "9e7eea3e4dbe946560e67064da27210602370175";
const PROWL_URL = "https://api.prowlapp.com/publicapi";
const PROWL_APP = "IMP";
function send_to_prowl(short="Short description", long="Longer description") {
    local data = {apikey=PROWL_KEY, url=http.agenturl(), application=PROWL_APP, event=short, description=long};
    http.post(PROWL_URL+"/add?" + http.urlencode(data), {}, "").sendasync(function(res) {
        if (res.statuscode != 200) {
            server.error("Prowl failed: " + res.statuscode + " => " + res.body);
        }
    })
}
// ***********************************************

// ******** email function ****************
function mailgun(emailFrom, emailTo, emailSubject, emailText) {
    const MAILGUN_URL = "https://api.mailgun.net/v2/smdimpgaragedoor.mailgun.org/messages";
    const MAILGUN_API_KEY = "key-7kzrf-cscad67mcq43-fxzr37ze6eq89";
    local auth = "Basic " + http.base64encode("api:"+MAILGUN_API_KEY);
    local text = http.urlencode({from=emailFrom, to=emailTo, subject=emailSubject, text=emailText});
    local req = http.post(MAILGUN_URL, {Authorization=auth}, text);
    local res = req.sendsync();
    if(res.statuscode != 200) {
        server.log("error sending email: "+res.body);
    }
}
// ******************************************

device.on("Activated", function(v) {
  send_to_prowl("Garage Door", "Activated");
});

device.on("buttonOpen", function(v) { 
  doorOpen = 1;
  openTime = time();
  send_to_prowl("Garage Door Opened", format("Temp=%0.1fF", v));    
});

device.on("buttonClosed", function(v) {
  doorOpen = 0;
  if (v.ctime > 3600) {
    send_to_prowl("Garage Door Closed", format("Temp=%0.1fF, OT=%0.1f Hrs", v.curTemp, v.ctime/3600.00));        
  }
  else {
    if (v.ctime>=60) {
      send_to_prowl("Garage Door Closed", format("Temp=%0.1fF, OT=%0.1f Min", v.curTemp, v.ctime/60.0));      
    }
    else {
      send_to_prowl("Garage Door Closed", format("Temp=%0.1fF, OT=%ds", v.curTemp, v.ctime));              
    }
  }
}
);

device.on("pleaseCloseDoor", function(v) {
  send_to_prowl("Garage Door left Open", "Please close door");
});

device.on("buttonClosedQuery", function(v) {
  send_to_prowl("Garage is Closed", format("Temp=%3.1fF",v));
  //mailgun("GarageDoor@imp.com", "2488214792@txt.att.net", "Door query", "Door closed, TMP=" + v);
});
    
device.on("buttonOpenQuery", function(v) {
  if (v.ctime > 3600) {
    send_to_prowl("Garage is Open", format("Temp=%0.1fF, OT=%0.1f Hrs", v.curTemp, v.ctime/3600.00));
  }
  else {
    if (v.ctime>=60) {
      send_to_prowl("Garage is Open", format("Temp=%0.1fF, OT=%0.1f Min", v.curTemp, v.ctime/60.0));
    }
    else {
      send_to_prowl("Garage is Open", format("Temp=%0.1fF, OT=%ds", v.curTemp, v.ctime));
    }
  }
  //mailgun("GarageDoor@imp.com", "2488214792@txt.att.net", "Door query", "Door open, TMP=" + v);
});

device.on("curTemp", function(v) { 
  curTemp = v;
//  server.log("curTemp=" + v)
});

device.on("doorWasOpen", function(v) { 
  doorOpen = 1;
  openTime = time();
});

device.on("doorWasClosed", function(v) { 
  doorOpen = 0;
  openTime = time();
});



function ping(request,res)
{
  server.log("Agent received request"); 
  server.log("json=" + request.body)
  try {
//    if (1) {    
    if ("siriQuery" in http.jsondecode(request.body)) {
      server.log("siriQuery requested")
      device.send("siriQuery", http.jsondecode(request.body));
      device.on("siriData", function(v) {
        server.log("got response from device")
        curTemp = v.curTemp;
        openTime = v.openTime;
        doorOpen = v.doorOpen;
        server.log("temp=" + curTemp + " openTime=" + openTime + " doorOpen=" + doorOpen);
      
        local data = {"door":doorOpen,"curTemp":curTemp,"openTime":openTime}
        local message = http.jsonencode(data);
        res.send(200, message); 
      });
    }
    else if ("ButtonOpen" in http.jsondecode(request.body)) { 
      device.send("siriQuery", http.jsondecode(request.body));
      device.on("siriData", function(v) {
        server.log("got response from device")
        curTemp = v.curTemp;
        openTime = v.openTime;
        doorOpen = v.doorOpen;
        server.log("temp=" + curTemp + " openTime=" + openTime + " doorOpen=" + doorOpen);
      
        if (doorOpen) {
          server.log("Already open")
          local data = {"door":doorOpen,"curTemp":curTemp,"openTime":openTime}
          local message = http.jsonencode(data);
          res.send(255, message);               
        }
        else {
          device.send("response",http.jsondecode(request.body));  
          res.send(200, "OK");
        }
      });      
    }
    else if ("ButtonClose" in http.jsondecode(request.body)){
      device.send("siriQuery", http.jsondecode(request.body));
      device.on("siriData", function(v) {
        server.log("got response from device")
        curTemp = v.curTemp;
        openTime = v.openTime;
        doorOpen = v.doorOpen;
        server.log("temp=" + curTemp + " openTime=" + openTime + " doorOpen=" + doorOpen);
      
        if (!doorOpen) {
          server.log("Already closed")
          local data = {"door":doorOpen,"curTemp":curTemp,"openTime":openTime}
          local message = http.jsonencode(data);
          res.send(255, message);               
        }
        else {
          device.send("response",http.jsondecode(request.body));  
          res.send(200, "OK");
        }
      });
    }
    else {
      device.send("response",http.jsondecode(request.body));  
      res.send(200, "OK");
    }
  }
  catch (e) {
    server.log("Invalid JSON")    
    res.send(200, "Invalid JSON string");
  }
}

http.onrequest(ping);


