//Visual parameters
int totalWidth = 400;

float targetTemp = 148;

import processing.serial.*;
Serial port;

// Global State.
float graphPlotPhase = -1;

ArrayList graphs = new ArrayList();

void setup()
{
  graphs.add(new ParamGraph(255, 0, 0, totalWidth, totalWidth/5, 'A', 32, 200));
  graphs.add(new ParamGraph(80, 0, totalWidth / 5, totalWidth, totalWidth / 5, 'B', -3, 3));
  graphs.add(new ParamGraph(160, 0,  2 * totalWidth / 5, totalWidth, totalWidth / 5, 'C', -3, 3));
  graphs.add(new ParamGraph(240, 0, 3 * totalWidth / 5, totalWidth, totalWidth / 5-2, 'D', -3, 3));  
 
  SumGraph sum = new SumGraph(255, 0, 4* totalWidth/5, totalWidth, totalWidth/5, -60, 60);
  // Add bottom three graphs to the sum graph.
  for(int i = 1; i < graphs.size(); ++i)
    sum.add((ParamGraph)graphs.get(i));
 
  graphs.add(sum);  
    
  String portName = Serial.list()[0]; // This works for arduinos on macs. 
                                    //For PCs, try a different number if you're not on COM1.
  port = new Serial(this, portName, 38400);
  size(totalWidth,totalWidth);
  frameRate(60);
  background(226);
  for(int i = 0; i < graphs.size(); ++i)
    ((ParamGraph)graphs.get(i)).draw();
  
  graphPlotPhase = 0;
  port.clear();
}

void draw()
{
  if(port.available() > 0)
  {
    String string = port.readStringUntil('\r');
    if(string != null)
    {
      string = trim(string);
      println(string);
      for(int i = 0; i < graphs.size(); ++i)
        ((ParamGraph)graphs.get(i)).handleString(string);
    }
  }
    
  for(int i = 0; i < graphs.size(); ++i)
    ((ParamGraph)graphs.get(i)).draw();
    
  stroke(255,0,0);
  float yStroke = (1 - (targetTemp - 32) / 168) * (totalWidth/5);
  line(0, yStroke, totalWidth,yStroke);
  graphPlotPhase+= 1.0 / totalWidth / 20;
  if(graphPlotPhase > 1)
    graphPlotPhase = 0;
}

class ParamGraph
{
  ParamGraph(float tBG, float tX, float tY, float tW, float tH, char tPrefix, float tMinVal, 
             float tMaxVal)
  {
    bg = tBG;
    x = tX;
    y = tY;
    w = tW;
    h = tH;
    prefix = tPrefix;
    minVal = tMinVal;
    maxVal = tMaxVal;
  }
  
  void draw()
  {    
    if(graphPlotPhase < 0)
    {
      noStroke();
      fill(0,0,bg);
      rect(x,y,w+1,h + 1);
    }
    else
    {
      stroke(0,0,bg);
      line(x + graphPlotPhase * w, y, x + graphPlotPhase * w, y + h);
    
      float drawVal = constrain( (currVal - minVal) / (maxVal - minVal), 0, 1);
      stroke(drawVal * 256);
      point(x + graphPlotPhase * w, y + h - (drawVal * h));
      
      // zero line in green.
      stroke(0,255,0);
      line(x, y + h/2, x + w, y + h/2);
    }
  }
  
  void handleString(String string)
  {
    if(prefix == string.charAt(0))
    {
      currVal = float(string.substring(1));
    } 
  }
  
  float bg;
  float x, y, w, h;
  float currVal = 0.5;
  float minVal,  maxVal;
  char prefix;
};

class SumGraph extends ParamGraph
{
  SumGraph(float tBG, float tX, float tY, float tW, float tH, float tMinVal, 
             float tMaxVal)
  {
    super(tBG, tX, tY, tW, tH, '\0', tMinVal, tMaxVal);
  }
  
  void handleString(String string)
  {
    // ignore the string and make the sum.
    float sum = 0;
    for(int i = 0; i < sumGraphs.size(); ++i)
      sum += ((ParamGraph)sumGraphs.get(i)).currVal;
      
    currVal = sum;
  }
  
  void add(ParamGraph graph)
  {
    sumGraphs.add(graph);
  }
  
  ArrayList sumGraphs = new ArrayList();
}
