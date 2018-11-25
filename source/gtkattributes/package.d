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
module gtkattributes;

template GtkAttributes()
{
   import std.traits;
   import std.exception : enforce;
   import gtk.Builder;

   // UDA to support both @ui and @ui("id");
   _ui ui(string id = "") { return _ui(id); }
   struct _ui { string id = ""; }

   // UDA to tag gtk events
   struct event(T)
   {
      string id; 
      string eventName;
      private alias eventType = T;
   }

   private string __getWidgetId(alias T, string s)()
   {
         // The member we're analyzing
      mixin("alias member = T." ~ s ~ ";");

      alias funcUDAs = getUDAs!(member, ui);    // @ui("id");
      alias structUDAs = getUDAs!(member, _ui); // @ui

      static if (funcUDAs.length + structUDAs.length == 0) return "";
      else if (funcUDAs.length + structUDAs.length > 1) assert(0, "You must use only one @ui attribute for `" ~ fullyQualifiedName!s ~ "`");
      else
      {
         static if (funcUDAs.length == 1) return s;
         else return structUDAs[0].id;
      }

   }

   // Version for non-static methods/var
   private void bindWidgets(T)(ref T obj, Builder b)
   {
      foreach( s; __traits( allMembers, T))
      {
         // The member we're analyzing
         static if (__traits(compiles, mixin("T." ~ s)))
         {
            mixin("alias member = T." ~ s ~ ";");
            
            static if (isExpressions!member)
            {
               enum widgetId = __getWidgetId!(T,s);

               static if (widgetId.length == 0) continue;
               else 
               {
                  auto tmpObj = b.getObject(widgetId);
                  enforce(tmpObj !is null, "Can't find any widget with id `" ~ widgetId ~ "`");
                  mixin("obj." ~ s ~ " = cast(typeof(member)) tmpObj;");
                  mixin("auto tmpMember = obj." ~ s ~ ";");
                  enforce(tmpMember !is null, "Can't convert `" ~ widgetId ~ "` to `" ~ fullyQualifiedName!(typeof(tmpMember)) ~ "`");
               }
            }
         }
      }
   }

   // Version for static methods/var
   private void bindWidgets(alias T)(Builder b)
   {
      foreach( s; __traits( allMembers, T))
      {
       
        // The member we're analyzing
         static if (__traits(compiles, mixin("T." ~ s)))
         {
            mixin("alias member = T." ~ s ~ ";");
            
            static if (isExpressions!member )
            {
               enum widgetId = __getWidgetId!(T,s);

               static if (widgetId.length == 0) continue;
               else {
                  auto tmpObj = b.getObject(widgetId);
                  enforce(tmpObj !is null, "Can't find any widget with id `" ~ widgetId ~ "`");
                  member = cast(typeof(member)) tmpObj;
                  enforce(member !is null, "Can't convert `" ~ widgetId ~ "` to `" ~ fullyQualifiedName!(typeof(member)) ~ "`");
               }
            }
         }
      }
   }

   // Version for static methods/var
   private void bindEvents(alias T)(Builder b)
   {
      import std.functional : toDelegate;

      foreach( s; __traits( allMembers, T))
      {
         // The member we're analyzing
         static if (__traits(compiles, mixin("T." ~ s)))
         {
            mixin("alias member = T." ~ s ~ ";");
            
            static if (isFunction!member)
            {
               alias udas = getUDAs!(member, event);

               static if (udas.length > 0)
                  foreach(u; udas)
                  {
                     enum hasMethod = __traits(hasMember, u.eventType, "add" ~ u.eventName);
                     static assert(hasMethod, "Can't find a method named `add" ~ u.eventName ~ "` for type `" ~ fullyQualifiedName!(u.eventType) ~"`");

                     auto tmpObj = b.getObject(u.id);
                     enforce(tmpObj !is null, "Can't find any widget with id `" ~ u.id ~ "`");
                     auto obj = cast(u.eventType) tmpObj;
                     enforce(obj !is null, "Can't convert `" ~  u.id ~ "` to `" ~ fullyQualifiedName!(u.eventType) ~ "`");
                     mixin ("obj.add" ~ u.eventName ~ "((&member).toDelegate());");
                  }
            }
         }
      }
   }

   // Version for non-static methods/var
   private void bindEvents(T)(ref T handler, Builder b)
   {
      foreach( s; __traits( allMembers, T))
      {
         static if (__traits(compiles, mixin("T." ~ s)))
         {
            mixin("alias member = T." ~ s ~ ";");
            
            static if (isFunction!member)
            {
               alias udas = getUDAs!(member, event);

               static if (udas.length > 0)
                  foreach(u; udas)
                  {
                     enum hasMethod = __traits(hasMember, u.eventType, "add" ~ u.eventName);
                     static assert(hasMethod, "Can't find a method named `add" ~ u.eventName ~ "` for type `" ~ fullyQualifiedName!(u.eventType) ~"`");

                     auto tmpObj = b.getObject(u.id);
                     enforce(tmpObj !is null, "Can't find any widget with id `" ~ u.id ~ "`");
                     auto obj = cast(u.eventType) tmpObj;
                     enforce(obj !is null, "Can't convert `" ~  u.id ~ "` to `" ~ fullyQualifiedName!(u.eventType) ~ "`");
                     mixin ("obj.add" ~ u.eventName ~ "(&handler." ~s ~");");
                  }
            }
         }
      }
   }

   private void bindAll(T)(ref T handler, Builder b)
   {
      bindWidgets(handler, b);
      bindEvents(handler, b);
   }

   private void bindAll(alias T)(Builder b)
   {
      bindWidgets!T(b);
      bindEvents!T(b);
   }

}