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

module resources;

immutable static VERSION = "1.0.2";
immutable static LAYOUT = import("layout.glade");
immutable static LOGO   = import("logo.raw");

enum LOGO_W = 512;
enum LOGO_H = 512;

// These lines should enable 3d cards on windows.
export extern(Windows) ulong NvOptimusEnablement = 0x00000001;
export extern(Windows) int AmdPowerXpressRequestHighPerformance = 1;
