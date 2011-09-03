#include "lcd_stuff.h"

int tempPotPin = 2;    // tempPotPin
int analogPin = 3;     // temperature sensor
int digitalPin = 8;    // relay
int turboPin = 6;      // turbo!
int ledPin = 13;       // on actual arduino boards this is pre-hooked up.
float targetTemp = 134; // target temperature
float loTemp = 120; // lowest temperature we can set
float hiTemp = 160; // highest temperature we can set
float cookTime = 2400000; // 40 minutes cook time (milliseconds)
float timeElapsed = 0;
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
  pinMode(turboPin, INPUT);
  digitalWrite(turboPin, HIGH);
  
  lcd_init();
  
  int val = analogRead(analogPin);    // read the input pin
  float temp = (((float)val) / 930.0) * 100;
  temp = temp * 1.8 + 32;
  
  for(int i= 0; i < numTemps; ++i)
    temps[i] = temp;
}

void SendMessage(char prefix, float message)
{
  Serial.print(prefix);
  Serial.println(message);
}

float aveTemp = 0;
float dAve = 0;

void heating_regime()
{
      digitalWrite(ledPin, HIGH);
      digitalWrite(digitalPin, HIGH);
      SendMessage('A', aveTemp);
      SendMessage('B', dAve);
      lcd_start_sending_numbers();
      lcd_send_number(aveTemp, 3, 1);
      lcd_send_number(targetTemp, 3, 0);
      lcd_send_oburt();
      lcd_stop_sending_numbers();
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

void main_regime()
{
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
    {
      cookTime -= delayTime;
      timeElapsed += delayTime;
    }
    if(cookTime < 0)
      doneCooking = 1;
    
    // Only do the rest at the relay rate.
    if(numSinceFlip * delayTime < relayRate)
      return;
 
    lcd_start_sending_numbers();
    lcd_send_number(aveTemp, 3, 1);
    lcd_send_number(targetTemp, 3, 0);
    lcd_send_number(timeElapsed / 1000 / 60, 3, 0);
    lcd_send_number((threshold / thresholdClip) * 99, 2, 0);
    lcd_stop_sending_numbers();
 
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

void turbo_mode()
{
      digitalWrite(ledPin, HIGH);
      digitalWrite(digitalPin, HIGH);
      SendMessage('A', aveTemp);
      SendMessage('B', dAve);
      lcd_start_sending_numbers();
      lcd_send_number(aveTemp, 3, 1);
      lcd_send_number(targetTemp, 3, 0);
      lcd_send_turbo();
      lcd_stop_sending_numbers();  
      lastState = 1;
      mode = 1;
}

void loop()
{
  int val = analogRead(analogPin);    // read the input pin
  float temp = (((float)val) / 930.0) * 100;
  temp = temp * 1.8 + 32;
  
  temps[tempCount++] = temp;
  tempCount = tempCount % numTemps;
 
  aveTemp = 0;
  for(int i = 0; i < numTemps; ++i)
   aveTemp += temps[i];
  aveTemp /= numTemps; 
  
  dAve = 0;
  for(int i = 0; i < numTemps - 1; ++i)
    dAve += temps[i + 1] - temps[i];
  dAve /= numTemps - 1;  
  
  // read target
  int targetVal = analogRead(tempPotPin);
  targetTemp = loTemp + (hiTemp - loTemp) * ((float)targetVal) / 1023;
    
  int turbo = digitalRead(turboPin);
  
  if(not turbo)
    turbo_mode();
  else if(mode == 0)
    heating_regime();
  else
    main_regime();
    
  delay(delayTime);  
}

