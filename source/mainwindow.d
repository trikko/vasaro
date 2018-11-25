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

module mainwindow;

import std.stdio;

import viewer;
import generator;
import std.experimental.all;

// GTK

import gtk.Builder;
import gtk.Main;
import gtk.Widget;
import gtk.Window;
import std.stdio;
import gtk.Button;
import gtk.Frame;
import gtk.CheckButton;
import gtk.ComboBoxText;
import gtk.ToggleButton;
import gtk.TreeView;
import gtk.Grid;
import gtk.ListStore;
import gtk.Box;
import gtk.CellRendererToggle;
import gtk.CellRendererText;
import glib.Timeout;
import gtk.Adjustment;

import gtk.LevelBar;
import gtk.ProgressBar;
import gtk.Label;
import gtk.Dialog;
import gtk.FileChooserDialog;
import gtk.FileChooserNative;
import gobject.Signals;
import gtk.FileChooserButton;
import gdk.Threads;
import gtk.MessageDialog;
import gtk.TreeViewColumn;
import gtk.TreePath;
import gtk.TreeSelection;

import std.concurrency;
import std.datetime;

import gtkattributes;

import std.algorithm : splitter;
import std.array : array;


mixin GtkAttributes;

@ui gtk.Window.Window   mainWindow;

// General
@ui CheckButton         showPreview;
@ui Adjustment          minDiameter;
@ui Adjustment          maxDiameter;
@ui Adjustment          resolution;
@ui Adjustment          vaseHeight;
@ui Adjustment          layerHeight;
@ui ComboBoxText        vaseProfile;

// Noise
@ui Adjustment          noiseAmplitude;
@ui Adjustment          noiseRotation;
@ui Adjustment          noiseXScale;
@ui Adjustment          noiseZScale;
@ui Adjustment          noiseRandomSeed;
@ui ComboBoxText        noiseStrength;
@ui Button              noiseRemove;
@ui Grid                noiseParamsGroup;
@ui Frame               noiseStrengthGroup;
@ui TreeView            noiseList;

// Just two fields: noise name and status (active/not active)
ListStore   noiseListStore;

// Timer I use to render
Timeout     renderTimeout;


bool  adjusting      = false; // To avoid conflicts between gui elements that are working on same params
int   currentNoise   = -1;

//  Closing window
@event!(gtk.Window.Window)("mainWindow", "OnHide")
void onWindowClose(Widget){ 
   viewer.stop();
   Main.quit(); 
}

// User toggle checkbox
@event!CheckButton("showPreview", "OnToggled")
void onShowPreview(ToggleButton t)
{
   if ((cast(CheckButton)t).getActive) viewer.start();
   else viewer.stop();
}

// User click export
@event!Button("about", "OnClicked")
void onAbout(Button t)
{
   import resources;
   import gtk.AboutDialog;
   import gdkpixbuf.Pixbuf;
   auto pixbuf = new Pixbuf(cast(char[])LOGO, GdkColorspace.RGB, true, 8, LOGO_W, LOGO_H, LOGO_W*4, null, null);
   pixbuf = pixbuf.scaleSimple(256,256,GdkInterpType.HYPER);

   auto dialog = new AboutDialog();
   dialog.setLicenseType(GtkLicense.GPL_3_0);
   dialog.setLogo(pixbuf);
   dialog.setProgramName("Vasaro");
   dialog.setVersion(VERSION);
   dialog.setWebsite("https://github.com/trikko/vasaro");
   dialog.setWebsiteLabel("https://github.com/trikko/vasaro");
   dialog.setComments("Your printable vase creator.");
   dialog.setCopyright("Copyright © 2018 Andrea Fontana");
   
   dialog.setTransientFor(mainWindow);
   dialog.run();
   dialog.hide();
}

// User click export
@event!Button("exportSTL", "OnClicked")
void onExport(Button t)
{
   import gtk.FileFilter;

   auto ff = new FileFilter();
   ff.addPattern("*.stl");
   ff.setName("Stereo Lithography interface format (*.stl)");

   FileChooserNative fn = new FileChooserNative("Export to...", mainWindow, GtkFileChooserAction.SAVE, "Ok", "Cancel");
   fn.setModal(true);
   fn.setDoOverwriteConfirmation(true);
   fn.addFilter(ff);
   fn.run;

   string filename = fn.getFilename();

   // "Cancel"
   if (filename.empty) return; 
   
   if (!filename.toLower.endsWith(".stl")) filename ~= ".stl";

   try
   {
      File f = File(filename, "wb");

      char[80] header;
      header[] = "Created with Vasaro.";

      f.rawWrite(header);
      f.rawWrite([cast(uint) model[currentModel].vertex.length / 3]);

      foreach(const ref v; model[currentModel].vertex.chunks(9).map!(x => cast(float[])x))
      {
         // I wont't calculate any surface normal
         f.rawWrite([0.0f,0.0f,0.0f]);  

         // Vertices
         f.rawWrite(v);

         // Reserved
         f.rawWrite([cast(ushort)0]); 
      }

      f.close();
   }
   catch (Exception e)
   {
      auto md = new MessageDialog(mainWindow, GtkDialogFlags.DESTROY_WITH_PARENT, GtkMessageType.ERROR, GtkButtonsType.CLOSE, "Error during file saving. Try changing file path.");
      md.run;
      md.destroy();   
   }
}

void updateNoiseInterface()
{
   bool noiseSelected = (noises.length > 0 && currentNoise >= 0);
   bool visible = (noiseSelected && noises[currentNoise].visible);

   noiseRemove.setSensitive(visible);
   noiseParamsGroup.setSensitive(visible);
   noiseStrengthGroup.setSensitive(visible);

   if (noiseSelected)
   {
      adjusting = true;
      
      for(int i = 0; i < 10; ++i)
      {
         auto tmpObj = cast(Adjustment)b.getObject("noiseScale" ~ i.to!string);
         tmpObj.setValue(noises[currentNoise].strengthPoints[i]);
      }
      noiseRotation.setValue(noises[currentNoise].rotation);
      noiseAmplitude.setValue(noises[currentNoise].amplitude);
      noiseXScale.setValue(noises[currentNoise].xScale);
      noiseZScale.setValue(noises[currentNoise].yScale);
      noiseRandomSeed.setValue(noises[currentNoise].seed);
      
      adjusting = false;
   }
   
   build();
}

int t;

@event!Button("noiseAdd", "OnClicked")
void onNoiseAdded(Button b)
{
   
   import gtk.TreeIter;
   import gtk.TreeSelection;
   import std.random : uniform;

   noises ~= Noise();
   noises[noises.length-1].seed = uniform(-10000, 10000);

   auto it = noiseListStore.createIter();
   noiseListStore.setValue(it, 0, true);
   noiseListStore.setValue(it, 1, "Noise #" ~ (noises.length-1).to!string);
   noiseList.getSelection().selectIter(it);

}


@event!Button("noiseRemove", "OnClicked")
void onNoiseRemoved(Button b)
{
   noiseListStore.remove(noiseList.getSelection().getSelected());

   for (size_t i = noises.length-1; i > currentNoise; --i)
      noises[i] = noises[i-1];
   
   noises.length--;
}

@event!ComboBoxText("vaseProfile", "OnChanged")
void onProfileSelected(ComboBoxText changed)
{
   final switch(changed.getActive)
   {
      case 0: // CONSTANT
         vaseProfileCheckPoints[] = 0.5; 
         break;
      
      case 1: // LINEAR
         for(int i = 0; i < 10; i++) vaseProfileCheckPoints[i] = i/9.0f;
         break;

      case 2: // EXP
         for(int i = 0; i < 10; i++) vaseProfileCheckPoints[i] = pow(i/9.0f,3);
         break;

      case 3: // SIN
         for(int i = 0; i < 10; i++) vaseProfileCheckPoints[i] = sin(i/9.0f*PI);
         break;

      case 4: // Custom 
         return;
   }

   adjusting = true;
   for(int i = 0; i < 10; ++i)
   {
      auto tmpObj = cast(Adjustment)b.getObject("radiusScale" ~ i.to!string);
      tmpObj.setValue(vaseProfileCheckPoints[i]);
   }
   adjusting = false;

   build();
}

@event!ComboBoxText("noiseStrength", "OnChanged")
void onNoiseStrengthSelected(ComboBoxText changed)
{
   final switch(changed.getActive)
   {
      case 0: // CONSTANT
         noises[currentNoise].strengthPoints[] = 1; 
         break;
      
      case 1: // LINEAR
         for(int i = 0; i < 10; i++) noises[currentNoise].strengthPoints[i] = i/9.0f;
         break;

      case 2: // EXP
         for(int i = 0; i < 10; i++) noises[currentNoise].strengthPoints[i] = pow(i/9.0f,3);
         break;

      case 3: // SIN
         for(int i = 0; i < 10; i++) noises[currentNoise].strengthPoints[i] = sin(i/9.0f*PI);
         break;

      case 4: // Custom 
         return;
   }

   adjusting = true;
   for(int i = 0; i < 10; ++i)
   {
      auto tmpObj = cast(Adjustment)b.getObject("noiseScale" ~ i.to!string);
      tmpObj.setValue(noises[currentNoise].strengthPoints[i]);
   }
   adjusting = false;

   build();
}

@event!Adjustment("noiseAmplitude", "OnValueChanged") @event!Adjustment("noiseXScale", "OnValueChanged")
@event!Adjustment("noiseZScale", "OnValueChanged") @event!Adjustment("noiseRandomSeed", "OnValueChanged") 
@event!Adjustment("noiseRotation", "OnValueChanged") @event!Adjustment("noiseRandomSeed", "OnValueChanged") 
void onNoiseParamsChanged(Adjustment changed)
{
   bool rebuild = true;
   
   if (changed == noiseAmplitude) generator.noises[currentNoise].amplitude = changed.getValue();
   else if (changed == noiseXScale) generator.noises[currentNoise].xScale = changed.getValue();
   else if (changed == noiseZScale) generator.noises[currentNoise].yScale = changed.getValue();
   else if (changed == noiseRandomSeed) generator.noises[currentNoise].seed = changed.getValue().to!long;
   else if (changed == noiseRotation) generator.noises[currentNoise].rotation = changed.getValue();
   else rebuild = false;
   
   if (rebuild)
   {
      build();
   }
}

@event!Adjustment("minDiameter", "OnValueChanged") @event!Adjustment("maxDiameter", "OnValueChanged")
@event!Adjustment("resolution", "OnValueChanged") @event!Adjustment("layerHeight", "OnValueChanged") @event!Adjustment("vaseHeight", "OnValueChanged")
void onGeneralParamsChanged(Adjustment changed)
{
   bool rebuild = true;
   if (changed == minDiameter) generator.minDiameter = changed.getValue;
   else if (changed == maxDiameter)  generator.maxDiameter = changed.getValue;
   else if (changed == resolution) generator.resolution = changed.getValue.to!int;
   else if (changed == vaseHeight) generator.vaseHeight = changed.getValue;
   else if (changed == layerHeight) generator.layerHeight = changed.getValue;
   else rebuild = false;
   

   if (rebuild)
   {
      build();
   }
}

@event!Adjustment("radiusScale0", "OnValueChanged") @event!Adjustment("radiusScale1", "OnValueChanged") @event!Adjustment("radiusScale2", "OnValueChanged")
@event!Adjustment("radiusScale3", "OnValueChanged") @event!Adjustment("radiusScale4", "OnValueChanged") @event!Adjustment("radiusScale5", "OnValueChanged")
@event!Adjustment("radiusScale6", "OnValueChanged") @event!Adjustment("radiusScale7", "OnValueChanged") @event!Adjustment("radiusScale8", "OnValueChanged")
@event!Adjustment("radiusScale9", "OnValueChanged")
void onProfileChange(Adjustment changed)
{
   if (adjusting) return;

   bool rebuild = true;

   for(int i = 0; i < 10; ++i)
   {
      auto tmpObj = cast(Adjustment)b.getObject("radiusScale" ~ i.to!string);
      vaseProfileCheckPoints[i] = tmpObj.getValue;
   }

   vaseProfile.setActive(4);
   build();


}

@event!Adjustment("noiseScale0", "OnValueChanged") @event!Adjustment("noiseScale1", "OnValueChanged") @event!Adjustment("noiseScale2", "OnValueChanged")
@event!Adjustment("noiseScale3", "OnValueChanged") @event!Adjustment("noiseScale4", "OnValueChanged") @event!Adjustment("noiseScale5", "OnValueChanged")
@event!Adjustment("noiseScale6", "OnValueChanged") @event!Adjustment("noiseScale7", "OnValueChanged") @event!Adjustment("noiseScale8", "OnValueChanged")
@event!Adjustment("noiseScale9", "OnValueChanged")
void onNoiseStrengthChange(Adjustment changed)
{
   if (adjusting) return;

   bool rebuild = true;

   for(int i = 0; i < 10; ++i)
   {
      auto tmpObj = cast(Adjustment)b.getObject("noiseScale" ~ i.to!string);
      noises[currentNoise].strengthPoints[i] = tmpObj.getValue;
   }

   noiseStrength.setActive(4);
   build();

}

bool needRebuild = true;
Builder b;
   
int main (string[] args)
{    
   // First start SDL ...
   import viewer;
   viewer.start();
   
   
   // ... then gtk.
   import resources;
   
   Main.init(args);
   b = new Builder();
   b.addFromString(LAYOUT);
   b.bindAll!mainwindow;

   // Add icon
   {
      import gdkpixbuf.Pixbuf;
      auto pixbuf = new Pixbuf(cast(char[])LOGO, GdkColorspace.RGB, true, 8, LOGO_W, LOGO_H, LOGO_W*4, null, null);
      
      // GTK+
      mainWindow.setIcon(pixbuf);

      // SDL
      viewer.setIcon(pixbuf.getPixels, pixbuf.getWidth, pixbuf.getHeight);
   }

   mainWindow.showAll();

   // For some obscures reasons, treeview won't work if
   // designed on Glade. I have to build it here instead.
   import gtk.TreeViewColumn;
   noiseListStore = new ListStore([GType.INT, GType.STRING]);

   TreeViewColumn column = new TreeViewColumn();
   column.setTitle( "Noise" );
   noiseList.appendColumn(column);

   CellRendererToggle cell_bool = new CellRendererToggle();
   column.packStart(cell_bool, 0 );
   column.addAttribute(cell_bool, "active", 0);

   CellRendererText cell_text = new CellRendererText();
   column.packStart(cell_text, 0 );
   column.addAttribute(cell_text, "text", 1);
   cell_text.setProperty( "editable", 1 );

   // Line toggled
   cell_bool.addOnToggled( delegate void(string p, CellRendererToggle){
      import gtk.TreePath, gtk.TreeIter;
        
      auto path = new TreePath( p );
      auto it = new TreeIter( noiseListStore, path );
      noiseListStore.setValue(it, 0, it.getValueInt( 0 ) ? 0 : 1 );
      
      auto index = it.getTreePath().getIndices()[0];

      noises[index].visible = it.getValueInt(0) == 1;
      updateNoiseInterface();
   });

   // Line changed
   cell_text.addOnEdited( delegate void(string p, string v, CellRendererText cell ){
      
      import gtk.TreePath, gtk.TreeIter;

      auto path = new TreePath( p );
      auto it = new TreeIter( noiseListStore, path );
      noiseListStore.setValue( it, 1, v );
   });

   noiseList.setModel(noiseListStore);
   noiseList.getSelection().addOnChanged(delegate(TreeSelection ts) { 
      auto selected = ts.getSelected();
      
      if (selected is null) currentNoise = -1;
      else currentNoise = selected.getTreePath().getIndices()[0];
      
      updateNoiseInterface();
   });


   // Start vase creation with default params
   generator.start();
   build();
   
   // Rendering loop (SDL)
   renderTimeout = new Timeout(1000/30, 
      delegate 
      { 
         if (viewer.isRunning) renderFrame(); 
         else if (showPreview.getActive()) showPreview.setActive(false);
         return true; 
      }, 
      false
   );
   
   // Main loop (Gtk+)
   Main.run();
   return 0;
}

