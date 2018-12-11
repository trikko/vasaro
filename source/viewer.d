/+
   Vasaro Copyright © 2018 Andrea Fontana
   This file is part of Vasaro.

   Vasaro is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   Vasaro is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with Vasaro.  If not, see <http://www.gnu.org/licenses/>.
+/

module viewer;

import generator;

import std.math : abs, sqrt, tan, PI;
import std.algorithm : max, min;

import derelict.opengl;
import derelict.sdl2.sdl;

public:

struct VaseModel
{
   float[]  vertex;
   float[]  vertexNormals;
}

__gshared VaseModel[2]  model;

void start()
{
   if (status.actual == ViewerStatus.STARTED)
      return;

   status.requested = ViewerStatus.STARTED;

   if (renderWindow == null) initRenderingWindow();
}

void stop() { status.requested = ViewerStatus.STOPPED; }
bool isRunning() { return !(status.requested == ViewerStatus.STOPPED && status.actual == ViewerStatus.STOPPED); }

void uninit()
{
   if (context && renderWindow)
   {
      SDL_GL_DeleteContext(context);
      SDL_DestroyWindow(renderWindow);
      SDL_Quit();

      debug
      {
         import std.stdio : writeln;
         writeln("SDL cleared.");
      }
   }
}

void setIcon(char* data, int width, int height)
{
   SDL_Surface* icon = SDL_CreateRGBSurfaceFrom(data, width, height, 32, width*4, 0x000000FF, 0x0000FF00, 0x00FF0000,0xFF000000);
   SDL_SetWindowIcon(renderWindow, icon);
   SDL_FreeSurface(icon);
}

private:

SDL_Window        *renderWindow  = null;
SDL_GLContext     context        = null;
__gshared GLuint 	vertexVbo; 
__gshared GLuint  vertexNormalsVbo; 

enum ViewerStatus
{
   STARTED = 0,
   STOPPED
}

struct ViewerStatusSync
{
   ViewerStatus requested  = ViewerStatus.STOPPED;
   ViewerStatus actual     = ViewerStatus.STOPPED;
}

__gshared ViewerStatusSync status;
__gshared bool             hasModel = false;

// Mixing-in opengl functions declarations
mixin glFreeFuncs!(GLVersion.gl21, true);

// Camera/Rendering settings
float    cameraRotationX = 0;
float    cameraRotationY = 0;
bool     autoRotate = true;
float    lastSign = 1;
size_t   lastRendered = -1;
float    currentSpeed = 1;
int      currentZoom = 0;

void setupScene(int w, int h)
{
	glMatrixMode(GL_PROJECTION);
   glLoadIdentity();

	int width = w, height = h;
	double aspect_root = sqrt(width * 1.0f / height);
	double nearest = 0.125; 
	
   float DEG2RAD = PI / 180;

   float front = 10.0f;
   float back = 500.0f;
   float fovY = 80.0f;
   float tangent = tan(fovY/2 * DEG2RAD); 
   float fheight = front * tangent; 
   float fwidth = fheight * width/height; 

   glFrustum(-fwidth, fwidth, -fheight, fheight, front, back);


	float[] light_ambient = [ 1.0, 1.0, 1.0, 0.5 ];
   float[] light_diffuse = [ 1.0, 1.0, 1.0, 0.5 ];
   float[] light_specular = [ 0.6, 0.6, 0.6, 0.6 ];
   float[] light_position = [ 1.0, 1.0, 100.0, 0.0 ];

   // Put lights into from POV
   glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();
	   
   glLightfv(GL_LIGHT0, GL_AMBIENT, light_ambient.ptr);
   glLightfv(GL_LIGHT0, GL_DIFFUSE, light_diffuse.ptr);
   glLightfv(GL_LIGHT0, GL_SPECULAR, light_specular.ptr);
   glLightfv(GL_LIGHT0, GL_POSITION, light_position.ptr);
}

private void createWindow()
{
   if (context) SDL_GL_DeleteContext(context);
   if (renderWindow) SDL_DestroyWindow(renderWindow);
            
   renderWindow = SDL_CreateWindow(
      "Vasaro Rendering", 
      SDL_WINDOWPOS_CENTERED,
      SDL_WINDOWPOS_CENTERED,
      512,
      512,
      SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE | SDL_WINDOW_SKIP_TASKBAR | SDL_WINDOW_MOUSE_CAPTURE
   );

   context = SDL_GL_CreateContext(renderWindow);


   // Some una-tantum settings for opengl rendering   
   glMatrixMode(GL_PROJECTION);
   glClearDepth(1.0f);
   glEnable (GL_DEPTH_TEST);
   glDepthFunc(GL_LEQUAL);
   glClearColor(0.1f, 0.18f, 0.24f, 1);  
   
   glEnable(GL_LIGHTING);
	glEnable(GL_CULL_FACE);
   glClearDepth(1.0f);
   glDepthFunc(GL_LEQUAL);
   glFrontFace(GL_CCW);
   glCullFace(GL_BACK);  

   glPushAttrib(GL_ENABLE_BIT | GL_COLOR_BUFFER_BIT | GL_TRANSFORM_BIT);
   glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA); 
   glEnable(GL_BLEND);
   glEnable(GL_MULTISAMPLE);  
   
	glEnable (GL_LIGHTING);
	glEnable (GL_LIGHT0);

   SDL_CaptureMouse(SDL_TRUE);

   status.actual = ViewerStatus.STARTED;
}

private void initBuffers()
{
   glGenBuffers(1, &vertexVbo);
   glGenBuffers(1, &vertexNormalsVbo);
}

private void initRenderingWindow()
{
   DerelictGL3.load();
   DerelictSDL2.load();

   SDL_Init(SDL_INIT_VIDEO);
   
   SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
   SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1);
   SDL_GL_SetAttribute(SDL_GL_MULTISAMPLEBUFFERS, 1);
   SDL_GL_SetAttribute(SDL_GL_MULTISAMPLESAMPLES, 4);
   SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

   createWindow();

   DerelictGL3.reload(); 

   initBuffers();
}



public bool renderFrame()
{
   float[3] clear_color = [0.10f, 0.18f, 0.24f];
   
   int windowWidth;
   int windowHeight;

   // Init scene
   {
      SDL_GetWindowSize(renderWindow, &windowWidth, &windowHeight);
      glViewport(0,0,windowWidth,windowHeight);
      glClear(GL_COLOR_BUFFER_BIT);
      setupScene(windowWidth, windowHeight);
   }

   // Hide request received
   if (status.actual == ViewerStatus.STARTED && status.requested == ViewerStatus.STOPPED) 
   {
      SDL_HideWindow(renderWindow);
      status.actual = ViewerStatus.STOPPED;
      hasModel = false;

      glDeleteBuffers(1, &vertexVbo);
      glDeleteBuffers(1, &vertexNormalsVbo);
   }

   // Show request received
   else if (status.actual == ViewerStatus.STOPPED && status.requested == ViewerStatus.STARTED) 
   {
      //SDL_ShowWindow(renderWindow);
      createWindow();
      initBuffers();

      status.actual = ViewerStatus.STARTED;
   }

   // Render frame if requested
   else if (status.actual == ViewerStatus.STARTED)
   {
      auto lastGenerated = lastGenerated();

      // Just started. Still no model available.
      if (lastGenerated != 0)
      {
         // New model to show?
         if (!hasModel || (lastRendered != lastGenerated))
         {            
            // Buffers binding
            if (model[currentModel].vertex.length > 0) {

               glBindBuffer(GL_ARRAY_BUFFER, vertexVbo);
               glBufferData(GL_ARRAY_BUFFER, model[currentModel].vertex.length*float.sizeof, model[currentModel].vertex.ptr, GL_STATIC_DRAW);
               glBindBuffer(GL_ARRAY_BUFFER, 0); 
               
               glBindBuffer(GL_ARRAY_BUFFER, vertexNormalsVbo);
               glBufferData(GL_ARRAY_BUFFER, model[currentModel].vertexNormals.length*float.sizeof, model[currentModel].vertexNormals.ptr, GL_STATIC_DRAW);
               glBindBuffer(GL_ARRAY_BUFFER, 0); 
            }

            hasModel = true;
            lastRendered = lastGenerated;
         }

         if(hasModel) renderVase();
      }
   }
   
   // Handling window event
   SDL_Event event;
   while (SDL_PollEvent(&event))
   {
      if (
         // Hide window on closing request
         event.type == SDL_QUIT 
         
         // If window is minimieze
         || (event.type == SDL_WINDOWEVENT && event.window.event == SDL_WINDOWEVENT_MINIMIZED)

         // Also on escape-button press
         || (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)
      ) stop();

      // Moving mouse with left button down
      else if (event.type == SDL_MOUSEMOTION && (event.motion.state & SDL_BUTTON_LMASK) == SDL_BUTTON_LMASK)
      {
         
         cameraRotationX += 2*PI/360*event.motion.yrel*10;
         cameraRotationX = max(-50, min(50, cameraRotationX));
         
         cameraRotationY += 2*PI/360*event.motion.xrel*10;
         currentSpeed = 2*PI/360*event.motion.xrel*10;
         
         if (currentSpeed == 0) currentSpeed = 0.1f;
         lastSign = event.motion.xrel >= 0?1:-1;
      }

      // I stop autorotation when user has left button down!
      else if (event.type == SDL_MOUSEBUTTONDOWN && event.button.button == SDL_BUTTON_LEFT)
      {
         autoRotate = false;
         currentSpeed = lastSign*0.1;
      }
      else if (event.type == SDL_MOUSEBUTTONUP && event.button.button == SDL_BUTTON_LEFT) autoRotate = true;
      
      // Zoom
      else if (event.type == SDL_MOUSEWHEEL)
      {
         currentZoom += event.wheel.y;
         currentZoom = max(-20, min(5, currentZoom));
      }
   }

   // Send back buffer to window
   SDL_GL_SwapWindow(renderWindow);
   return true;
}

private void renderVase()
{
   // Clear the whole scene
   glClear(GL_DEPTH_BUFFER_BIT);
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();

   // Zoom
   glTranslatef(0.0f, -50.0 + currentZoom * 3 , -150.0 + currentZoom * 5);
   
   // Rotation
   glRotatef(cameraRotationX, 1.0, 0.0, 0.0);
 	glRotatef(cameraRotationY, 0.0, 1.0, 0.0);
        
   if (autoRotate)
   {
      cameraRotationY = (cameraRotationY + currentSpeed);

      // Accelerate / Decelerate
      if (abs(currentSpeed) > 1) 
      {
         currentSpeed *= 0.97;
         if (abs(currentSpeed) < 1) currentSpeed  = 1* lastSign;
      }
      else if(abs(currentSpeed) < 1)
      {
         currentSpeed *= 1.05;
         if (abs(currentSpeed) > 1) currentSpeed  = 1 * lastSign;
      }
   }
   if (cameraRotationY > 360) cameraRotationY -= 360;
   if (cameraRotationY < 0) cameraRotationY += 360;

   
   // Gummy material
   float[] no_mat = [0.0f, 0.0f, 0.0f, 1.0f];
   float[] mat_ambient = [0.05f, 0.05f, 0.05f, 1.0f];
   float[] mat_ambient_color = [0.8f, 0.8f, 0.2f, 1.0f];
   float[] mat_diffuse = [0.8f, 0.7f, 0.1f, 1.0f];
   float[] mat_specular = [1.0f, 1.0f, 1.0f, 1.0f];
   float high_shininess = 80.0f;
   
   glMaterialfv(GL_FRONT, GL_AMBIENT, no_mat.ptr);
   glMaterialfv(GL_FRONT, GL_DIFFUSE, mat_diffuse.ptr);
   glMaterialfv(GL_FRONT, GL_SPECULAR, mat_specular.ptr);
   glMaterialf(GL_FRONT, GL_SHININESS, high_shininess);
   glMaterialfv(GL_FRONT, GL_EMISSION, mat_ambient.ptr);

   // Push vertices and triangles
	glEnableClientState(GL_VERTEX_ARRAY);
	glBindBuffer(GL_ARRAY_BUFFER, vertexVbo);
	glVertexPointer(3, GL_FLOAT, 0, cast(void*)(0));

	glEnableClientState(GL_NORMAL_ARRAY);
	glBindBuffer(GL_ARRAY_BUFFER, vertexNormalsVbo);
	glNormalPointer(GL_FLOAT, 0, cast(void*)(0));

	glBindBuffer(GL_ARRAY_BUFFER, 0); 
	glDrawArrays(GL_TRIANGLES, 0, cast(int)(model[currentModel].vertex.length/3));
	glDisableClientState(GL_VERTEX_ARRAY);   
}

