int analogPin = 3;     // temperature sensor
int digitalPin = 8;    // relay
int ledPin = 13;       // on actual arduino boards this is pre-hooked up.
float targetTemp = 133; // target temperature
float cookTime = 2400000; // 40 minutes cook time (milliseconds)

// All times in milliseconds.

// relay flipping state
int numSinceFlip = 0;
int lastState = 0;
int lastStateForDoneBlink = 0;

// PD parameters
float proportional = .8;
float derivative = 10;
float maxContribution = 2.0; // each of the PD contributions is clipped here.
float thresholdClip = .3; // This is the maximum total output for PD mode (0-1).

// Heating regime parameters
float warmUpTime = 60000;
float coolDownTime = 180000;

// Cooking counter parameters
float tempDiffForCook = 1; // start the cook time counter when we're one degree off.
int doneCooking = 0;

// random parameters
int delayTime = 100;
int relayRate = 1000;

// temperature average
int numTemps = 50;
float temps[50];
int tempCount;

// 0 means heating regime, 1 means PD regime
int mode = 0;

void setup()
{
  Serial.begin(38400);          //  setup serial
  analogReference(INTERNAL);
  pinMode(ledPin, OUTPUT);   
  pinMode(digitalPin, OUTPUT);
  digitalWrite(digitalPin, LOW);
  for(int i= 0; i < numTemps; ++i)
    temps[i] = 0;
}

void SendMessage(char prefix, float message)
{
  Serial.print(prefix);
  Serial.println(message);
}

void loop()
{
  int val = analogRead(analogPin);    // read the input pin
  float temp = (((float)val) / 930.0) * 100;
  temp = temp * 1.8 + 32;
  
  temps[tempCount++] = temp;
  tempCount = tempCount % numTemps;
 
  float aveTemp = 0;
  for(int i = 0; i < numTemps; ++i)
   aveTemp += temps[i];
  aveTemp /= numTemps; 
  
  float dAve = 0;
  for(int i = 0; i < numTemps - 1; ++i)
    dAve += temps[i + 1] - temps[i];
  dAve /= numTemps - 1;  
  
  delay(delayTime);  
    
  if(mode == 0)
  {
      digitalWrite(ledPin, HIGH);
      digitalWrite(digitalPin, HIGH);
      SendMessage('A', aveTemp);

      SendMessage('B', dAve);
      if(aveTemp + (dAve * warmUpTime / delayTime) > targetTemp)
      {
        digitalWrite(digitalPin, LOW);
        digitalWrite(ledPin, LOW);
        SendMessage('A', dAve);
        SendMessage('B', aveTemp);
        SendMessage('C', aveTemp + (dAve * warmUpTime / delayTime));
        mode = 1;
        delay(coolDownTime);
      }
  }
  else
  {

    numSinceFlip++;
    
    float dErrorAverage = 0;
    float tLastErr = temps[0] - targetTemp;
    for(int i = 1; i < numTemps; ++i)
    {
      dErrorAverage += (temps[i] - targetTemp) - tLastErr;
      tLastErr = temps[i] - targetTemp;
    }
    dErrorAverage /= numTemps - 1;  
    
    float error = targetTemp - aveTemp;
    float kp = constrain(proportional * error, -maxContribution, maxContribution);
    float kd = constrain(derivative * dErrorAverage, -maxContribution, maxContribution);

    float sum = constrain((kp + kd) / maxContribution, 0, 1);

    // use a non-linear scaling for sum into threshold
    float threshold = (sum * sum)/ 2;
    
    // clip the threshold
    threshold = constrain(threshold, 0, thresholdClip);
    
    int randNum = random(0,100);
    float randFloat = randNum / 100.0;   
    
    // Deal with cooking timer.
    if(error < tempDiffForCook)
      cookTime -= delayTime;
    if(cookTime < 0)
      doneCooking = 1;
    
    // Only do the rest at the relay rate.
    if(numSinceFlip * delayTime < relayRate)
      return;
 
    SendMessage('A', aveTemp);
    SendMessage('B', kp);
    SendMessage('C', kd);
    SendMessage('D', threshold);
    SendMessage('E', randFloat);
    numSinceFlip = 0;
    
    if(doneCooking)
    {
      if(lastStateForDoneBlink)
        digitalWrite(ledPin, HIGH);
      else
        digitalWrite(ledPin, LOW);
      lastStateForDoneBlink = !lastStateForDoneBlink;
    }
    
    int relayOn = 0;
    
    if((kp + kd)  > 0)
      if(randFloat <= threshold)
        relayOn = 1;
    
    if(error < 0)
      relayOn = 0;
    
    if(relayOn == lastState)
      return;
    
    if(relayOn == 0)
    {
      lastState = 0;
      digitalWrite(digitalPin, LOW);
      if(0 == doneCooking)
        digitalWrite(ledPin, LOW);
    }
    else
    {
      lastState = 1;
      digitalWrite(digitalPin, HIGH);
      if(0 == doneCooking)
        digitalWrite(ledPin, HIGH);
    }
  }
}

