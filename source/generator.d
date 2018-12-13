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
module generator;

import std.concurrency;
import std.conv : to;

import opensimplexnoise;
import vec3;
import viewer;

public:

__gshared Tid generatorTid;
__gshared size_t currentModel = 0;  // 0 or 1
__gshared float minDiameter = 60;
__gshared float maxDiameter = 100;
__gshared int resolution = 300;
__gshared float vaseHeight = 100;
__gshared float layerHeight = 0.2;

__gshared float[10] vaseProfileCheckPoints = [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5];

struct Noise
{
   long  seed        = 0;
   float xScale      = 3;
   float yScale      = 3;
   float amplitude   = 2;
   float rotation    = 0;
   float[10] strengthPoints = [1,1,1,1,1,1,1,1,1,1];
   bool visible = true;
}

__gshared Noise[] noises;

void start()
{
   if (gs_actual != 0)
      return;

   generatorTid = spawn(&initGenerator);
   generatorTid.setMaxMailboxSize(1, OnCrowding.ignore);  // Avoid spam 

   debug {
      import std.stdio : writeln;
      writeln("Generator started.");
   }
}

void build()
{
   import core.thread;
   gs_requested++;
   send(generatorTid, true);
}

bool isRunning()  { return true; /*gs_actual != GeneratorStatus.STOPPED;*/ }
bool isCompleted()  { return gs_actual == gs_requested; /*gs_actual == GeneratorStatus.COMPLETED;*/ }

size_t lastGenerated() { return gs_actual; }

private:

__gshared size_t gs_requested = 1;
__gshared size_t gs_actual = 0;

import std.datetime.stopwatch : StopWatch;

void initGenerator()
{
   try
   {
      // Sync with other threads
      while(true)
      {
         bool received = receiveOnly!bool; 
         if (gs_actual != gs_requested) createVase();
      }
   }

   // That's ok, app was closed.
   catch (OwnerTerminated ot)  { debug { import std.stdio; writeln("Generator cleared."); } }
}


void createVase()
{
   import std.stdio;
   import std.typecons : Tuple, tuple;
   import std.array : uninitializedArray;
   import std.parallelism : parallel;
   import std.range : iota;
   import std.math : sin, cos, PI;
   import std.datetime.stopwatch : StopWatch;
   import std.experimental.allocator;
   import std.experimental.allocator.mallocator : Mallocator;
   
   // Calculate spline coeff. from ten points equally-separated
   float[4][10] naturalSpline(float[10] y)
   {
      float[4][10] results;
      float[9] mu;
      float[10] z;
      float g = 0;

      mu[0] = 0;
      z[0] = 0;
      
        for (int i = 1; i < 9; i++) {
            g = 4 - mu[i -1];
            mu[i] = 1 / g;
            z[i] = (3 * (y[i + 1]  - y[i] * 2 + y[i - 1]) - z[i - 1]) / g;
        }

        float[9] b;
        float[10] c;
        float[9] d;

        z[9] = 0;
        c[9] = 0;

        for (int j = 8; j >=0; j--) {
            c[j] = z[j] - mu[j] * c[j + 1];
            b[j] = (y[j + 1] - y[j]) - 1 * (c[j + 1] + 2 * c[j]) / 3;
            d[j] = (c[j + 1] - c[j]) / 3;
        }

        for (int i = 0; i < 9; i++) {
            results[i][0] = y[i];
            results[i][1] = b[i];
            results[i][2] = c[i];
            results[i][3] = d[i];
        }

        return results;
   }

   // Using coeff. calculated above we can approximate y value for x.
   // Used to interpolate points set by user
   float interpolateSpline(float[4][10] coeff, float x)
   {
      size_t xx = x.to!int;
      float val = x-xx;
      auto cur = coeff[xx];
      return cur[0] + cur[1]*val + cur[2]*val*val + cur[3]*val*val*val;
   }

   // Some benchmark
   StopWatch swGen;
   swGen.start();
   
   auto noisesCopy = noises;

   size_t current = gs_requested;               // Asked revision
   size_t candidateModel = (currentModel+1)%2;  // Buffer we're working on. No errors? It will become the rendered model.

   // If another request is queued, we can interrupt this one.
	bool continueProcessing() { return (gs_requested == current); }

	float min_diameter = minDiameter;
	float max_diameter = maxDiameter;
	int res = resolution;

	float height = vaseHeight;
	float layer = layerHeight;  

	auto layersCnt                   = (height/layer).to!size_t;
	
   Vec3[][] sideMeshVertex          = Mallocator.instance.makeMultidimensionalArray!Vec3(res, layersCnt); 
   Vec3[][] sideMeshVertexNormals   = Mallocator.instance.makeMultidimensionalArray!Vec3(res, layersCnt); 

   scope(exit)
   {
      Mallocator.instance.disposeMultidimensionalArray(sideMeshVertex);
      Mallocator.instance.disposeMultidimensionalArray(sideMeshVertexNormals);
   }

   struct Coords { size_t x; size_t y; }
   Coords[] sideMeshVertexNormalsMap = null;

	float xC = 0.0f;


   //
   // RADIUS VARIANCE
   //

   float[] layersRadiusFactor = Mallocator.instance.makeArray!float(layersCnt);
   scope(exit) Mallocator.instance.dispose(layersRadiusFactor);

   {
      // I want to limit function inside [-1;1] interval
      float maxDiameterFactor = 1;
      float minDiameterFactor = -1;

      
      auto layerSplineCoeff = naturalSpline(vaseProfileCheckPoints);
      foreach(i, ref lf; layersRadiusFactor)
      {
         lf = interpolateSpline(layerSplineCoeff, 9.0f*i*1.0f/layersCnt)*2-1;
         if (lf < minDiameterFactor) minDiameterFactor = lf;
         else if (lf > maxDiameterFactor) maxDiameterFactor = lf;
      }
   }

   //
   // NOISE
   //

   auto noiseMesh = Mallocator.instance.makeMultidimensionalArray!float(res, layersCnt); 
   scope(exit) Mallocator.instance.disposeMultidimensionalArray(noiseMesh);

   immutable meanDiameter  = (min_diameter+max_diameter)/2;
   immutable diameterDelta = (max_diameter-min_diameter)/2;
    
   double min = double.max;
   double max = -double.max;

   
   float[4][10][] noiseCoeff;
   noiseCoeff.length = noisesCopy.length;

   OpenSimplexNoise!float[] sn;
   sn.length = noisesCopy.length;

   // Noise strength
   foreach(i, ref n; noisesCopy)
   {
      if (!n.visible) continue;
      sn[i] = new OpenSimplexNoise!float(n.seed);
      noiseCoeff[i] = naturalSpline(n.strengthPoints);
   }
   

   auto circumference = meanDiameter * PI;
   bool hasNoise = false;

   // Calculate noise for each point of mesh
   foreach(i, ref n; noisesCopy)
   {
      if (!n.visible) continue;

      auto twist = n.rotation/layersCnt;

      immutable xScaleNorm = n.xScale*circumference/200;
      immutable yScaleNorm = 4*n.yScale*height/200;
      
      foreach(size_t x; parallel(iota(cast(size_t)0, res)))
      {
         auto xx = cast(float)(x)/(res-1);
         auto noiseMeshPtr = &noiseMesh[x][0];

         if (!continueProcessing()) continue;

         foreach(size_t y; 0 .. layersCnt)
         {
            auto yy = cast(float)(y)/(layersCnt-1);
            float noise = sn[i].eval(
               cos(2*PI*(xx+twist*y))*xScaleNorm, 
               sin(2*PI*(xx+twist*y))*xScaleNorm,
               yy*yScaleNorm
            )
            *n.amplitude
            *interpolateSpline(noiseCoeff[i], 9.0f*y/layersCnt)*2-1;  
           
            if (!hasNoise) noiseMeshPtr[y] = noise;
            else noiseMeshPtr[y] += noise;
            
            if (noise > max) max = noise;
            else if (noise< min) min = noise;
         }
      }

      hasNoise = true;
   }  

   // Sum all the things up
   foreach(size_t x; parallel(iota(cast(size_t)0, res)))
   {
      if (!continueProcessing()) continue;
      auto sideMeshVertexPtr = &sideMeshVertex[x][0];

		foreach(size_t y; (iota(0,layersCnt)))
      {
         immutable curWidth = meanDiameter + diameterDelta * layersRadiusFactor[y];
         sideMeshVertexPtr[y] = Vec3((curWidth/2)*cos(2*PI/(res-1)*x),y*layer,(curWidth/2)*sin(2*PI/(res-1)*x));
			
         if (hasNoise)
         {
            immutable noise = (noiseMesh[x][y] - min);
            sideMeshVertexPtr[y].x += noise * cos(2*PI/(res-1)*x);
            sideMeshVertexPtr[y].z += noise * sin(2*PI/(res-1)*x);
         }

         sideMeshVertexNormals[x][y] = Vec3(0,0,0);
		}
   }

   if (!continueProcessing) return;

   // Ok, we can guess how many triangle we need 
   immutable size_t side_vertex_coords_count = 
      (layersCnt-2)     // Number of layers
      * (res-1)         // Number of points per layer
      * 3               // 3 coords for each point
      * 3               // 3 points for each triangle
      * 2               // 2 triangle for each point

      + 2               // Last two layers
      * (res-1)         // Number of points per layer
      * 3               // 3 coords for each point
      * 3               // 3 points for each triangle
      * 1;              // 1 triangle for each point 0

   immutable size_t base_vertex_coords_count =
      (res-1)           // Triangles
      * 3               // 3 coords for each point
      * 3;              // 3 points for each triangle

   immutable size_t total_vertex_coords_count = 
      side_vertex_coords_count 
      + 2               // Top and bottom layer
      * base_vertex_coords_count;

   if (model[candidateModel].vertex !is null) 
      Mallocator.instance.dispose(model[candidateModel].vertex);

   if (model[candidateModel].vertexNormals !is null) 
      Mallocator.instance.dispose(model[candidateModel].vertexNormals);

   model[candidateModel].vertex        = Mallocator.instance.makeArray!float(total_vertex_coords_count);
   model[candidateModel].vertexNormals = Mallocator.instance.makeArray!float(total_vertex_coords_count);
   
   sideMeshVertexNormalsMap = Mallocator.instance.makeArray!Coords(side_vertex_coords_count/3);
   scope(exit) Mallocator.instance.dispose(sideMeshVertexNormalsMap);

   import core.atomic;
   shared(size_t) globalParallelIdx = 0;

   // Parallelization: to avoid multithread problems first we do all even rows, then all the odd.
	foreach(idx; 0..2)
	foreach (size_t x; parallel(iota(size_t(idx),res-1,2)))
	{
      if (!continueProcessing()) continue;
      
      foreach(size_t y; 0..layersCnt)
      {
            
			if (y < layersCnt-1)
			{
            immutable parallelIdx = globalParallelIdx.atomicOp!"+="(1) - 1;
            auto vertexSlice = model[candidateModel].vertex[parallelIdx*9+0..parallelIdx*9+9];
            auto sideMeshVertexNormalsMapSlice = sideMeshVertexNormalsMap[parallelIdx*3..parallelIdx*3+3];
         
				const cur   = &sideMeshVertex[x][y];
				const right = &sideMeshVertex[x+1][y];
				const top   = &sideMeshVertex[x][y+1];

				immutable normal = (*top-*cur).crossProduct(*right-*cur);
				
            sideMeshVertexNormals[x][y] += normal;
            sideMeshVertexNormals[x+1][y] += normal;

            if (x+1 == res-1) sideMeshVertexNormals[0][y] += normal;
            
            sideMeshVertexNormals[x][y+1] += normal;

            vertexSlice[0..3] = cur.data[0..3];
            vertexSlice[3..6] = top.data[0..3];
            vertexSlice[6..9] = right.data[0..3];

				sideMeshVertexNormalsMapSlice[0] = Coords(x,y);
            sideMeshVertexNormalsMapSlice[1] = Coords(x+1,y);
            sideMeshVertexNormalsMapSlice[2] = Coords(x,y+1);
			}


			if (y > 0)
			{
            immutable parallelIdx = globalParallelIdx.atomicOp!"+="(1) - 1;
            auto vertexSlice = model[candidateModel].vertex[parallelIdx*9+0..parallelIdx*9+9];
            auto sideMeshVertexNormalsMapSlice = sideMeshVertexNormalsMap[parallelIdx*3..parallelIdx*3+3];
         
				auto cur     = &sideMeshVertex[x][y];
				auto right   = &sideMeshVertex[x+1][y];
				auto bottom  = &sideMeshVertex[x+1][y-1];

				immutable normal = (*right-*cur).crossProduct(*bottom-*cur);

            sideMeshVertexNormals[x][y] += normal;
            sideMeshVertexNormals[x+1][y] += normal;
            sideMeshVertexNormals[x+1][y-1] += normal;

            if (x+1 == res-1)
            {
               sideMeshVertexNormals[0][y] += normal;
               sideMeshVertexNormals[0][y-1] += normal;
            }

            vertexSlice[0..3] = cur.data[0..3];
            vertexSlice[3..6] = right.data[0..3];
            vertexSlice[6..9] = bottom.data[0..3];

			   sideMeshVertexNormalsMapSlice[0]  = Coords(x,y);
            sideMeshVertexNormalsMapSlice[1]  = Coords(x+1,y);
            sideMeshVertexNormalsMapSlice[2]  = Coords(x+1,y-1);
			}
			
		}
	}

   if (!continueProcessing) return;

   // Top and bottom base
   {
      size_t startingIdx = side_vertex_coords_count;
      for(size_t x = 1; x < res; ++x)
      {
         if (!continueProcessing()) return;
            
         auto b = &sideMeshVertex[x-1][0];
         auto c = &sideMeshVertex[x][0];

         model[candidateModel].vertex[startingIdx+0..startingIdx+3] = [0.0f, 0.0f, 0.0f];    // All triangles have a vertex in base center
         model[candidateModel].vertex[startingIdx+3..startingIdx+6] = b.data[0..3];
         model[candidateModel].vertex[startingIdx+6..startingIdx+9] = c.data[0..3];
         startingIdx += 9;
      }

      for(size_t x = 1; x < res; ++x)
      {
         if (!continueProcessing()) return;
            
         auto b = &sideMeshVertex[x][layersCnt-1];
         auto c = &sideMeshVertex[x-1][layersCnt-1];

         model[candidateModel].vertex[startingIdx+0..startingIdx+3] = [0.0f, layer*(layersCnt-1), 0.0f];
         model[candidateModel].vertex[startingIdx+3..startingIdx+6] = b.data[0..3];
         model[candidateModel].vertex[startingIdx+6..startingIdx+9] = c.data[0..3];
         startingIdx += 9;
      }
   }

   // Sum up all the normals
   foreach(i, nIdx; parallel(sideMeshVertexNormalsMap))
   {
	   if (!continueProcessing()) continue;

      // Normals of side mesh
      if (i < side_vertex_coords_count / 3) model[candidateModel].vertexNormals[i*3..i*3+3] = sideMeshVertexNormals[nIdx.x][nIdx.y].normalized().data[0..3];
   }

   // Normals of two bases
   {
      size_t startingIdx = sideMeshVertexNormalsMap.length;
      foreach(i; parallel(iota(startingIdx,startingIdx+(res-1)*3)))
         model[candidateModel].vertexNormals[i*3..i*3+3] = [0, -1, 0];

      startingIdx += (res-1)*3;
      foreach(i; parallel(iota(startingIdx,startingIdx+(res-1)*3)))
         model[candidateModel].vertexNormals[i*3..i*3+3] = [0, 1, 0];
   }

   swGen.stop();

   if (!continueProcessing()) return;

   gs_actual = current;

   auto oldModel = currentModel;
   currentModel = candidateModel;

   Mallocator.instance.dispose(model[oldModel].vertex);
   Mallocator.instance.dispose(model[oldModel].vertexNormals);

   model[oldModel].vertex = null;
   model[oldModel].vertexNormals = null;
   
   writeln("Vase regenerated in: ", swGen.peek.total!"msecs", "ms");
}