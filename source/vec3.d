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
module vec3;

struct Vec3
{
	import std.traits: isNumeric;
   import core.simd;

   version(D_SIMD) { pragma(msg, "SIMD enabled"); }
   else { pragma(msg, "SIMD not enabled"); }

   union 
   { 
      version(D_SIMD)
      {
         float4 	simd = 0;
      }

      float[3] 	data; 
      struct 	   { float x; float y; float z; }
   }

   // Better avoid copy c-tors
   @disable this(this); 
   
   this(float x, float y, float z) 	{ this.data = [x,y,z]; }
   this(float[3] data) 				   { this.data[] = data[]; } 
   
   Vec3 opBinary(string op)(const ref Vec3 v) const if((op == "+") || (op == "-") || (op == "*") || (op == "/")) {
      Vec3 result;
      version(D_SIMD) { result.simd =  mixin("simd" ~ op ~ "v.simd"); }
      else { result.data[] = mixin("data[]" ~ op ~ "v.data[]"); }
      return result;
   }
   
   Vec3 opBinary(string op, T)(const T v) const if(((op == "+") || (op == "-") || (op == "*") || (op == "/")) && isNumeric!T) {
      Vec3 result;
      version(D_SIMD) { result.simd =  mixin("simd" ~ op ~ "v"); }
      else { result.data[] = mixin("data[]" ~ op ~ "v"); }
      return result;
   }
   
   void opOpAssign(string op)(const ref Vec3 v) if((op == "+") || (op == "-") || (op == "*") || (op == "/")) {
      version(D_SIMD) { mixin("simd = simd " ~ op ~ "v.simd;"); }
      else { mixin("this.data[] " ~ op ~ "= v.data[];"); }
   }
   
   void opOpAssign(string op, T)(const T v) if(((op == "+") || (op == "-") || (op == "*") || (op == "/")) && isNumeric!T) {
      version(D_SIMD) { mixin("simd = simd " ~ op ~ "v;"); }
      else { mixin("this.data[] " ~ op ~ "= v;"); }
   }
   
   void opAssign(const ref Vec3 v) 
   {
      version(D_SIMD) { simd = v.simd; }
      else { this.data[] = v.data[]; } 
   }

   void opAssign(Vec3 v) 
   { 
      version(D_SIMD) { simd = v.simd; }
      else { this.data[] = v.data[]; }
   }

   @property float magnitude() const
   { 
      import std.math : sqrt;
      return sqrt(x*x + y*y + z*z);
   }
   
   Vec3 normalized() const
   {
      auto m = magnitude();
      if (m == 0) return Vec3();
      else return this / magnitude; 
   }
   
   void normalize() 
   { 
      auto m = magnitude();
      if (m == 0) return;
      else this /= magnitude; 
   }
   
   Vec3 dotProduct   (const ref Vec3 v) const  { return this*v; }
   Vec3 crossProduct (Vec3 v)           const  { return Vec3(y*v.z - z*v.y, z*v.x - x*v.z, x*v.y - y*v.x); }

}