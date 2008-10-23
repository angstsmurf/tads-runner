#charset "us-ascii"

/* 
 *   Copyright (c) 2000, 2006 Michael J. Roberts.  All Rights Reserved. 
 *   
 *   TADS 3 Library - settings file management
 *   
 *   This is a framework that the library uses to keep track of certain
 *   preference settings - things like the NOTIFY, FOOTNOTES, and EXITS
 *   settings. 
 *   
 *   The point of this framework is "global" settings - settings that apply
 *   not just to a particular game, but to all games that have a particular
 *   feature.  Things like NOTIFY, FOOTNOTES, and some other such features
 *   are part of the standard library, so they tend to be available in most
 *   games.  Furthermore, they tend to work more or less the same way in
 *   most games.  As a result, a given player will probably prefer to set
 *   the options a particular way for most or all games.  If a player
 *   doesn't like score notification, she'll probably dislike it across the
 *   board, not just in certain games.
 *   
 *   This module provides the internal, programmatic core for managing
 *   global preferences.  There's no UI in this part of the implementation;
 *   the adv3 library layers the UI on top via the settingsUI object, but
 *   other alternative UIs could be built using the API provided here.
 *   
 *   The framework is extensible - there's an easy, structured way for
 *   library extensions and games to add their own configuration variables
 *   that will be automatically managed by the framework.  All you have to
 *   do to create a new configuration variable is to create a SettingsItem
 *   object to represent it.  Once you've created the object, the library
 *   will automatically find it and manage it for you.
 *   
 *   This module is designed to be separable from the adv3 library, so that
 *   alternative libraries or stand-alone (non-library-based) games can
 *   reuse it.  This file has no dependencies on anything in adv3 (at
 *   least, it shouldn't).  
 */

#include <tads.h>
#include <file.h>


/* ------------------------------------------------------------------------ */
/*
 *   A settings item.  This encapsulates a single setting variable.  When
 *   we're saving or restoring default settings, we'll simply loop over all
 *   objects of this class to get or set the current settings.
 *   
 *   Note that we don't make any assumptions in this base class about the
 *   type of the value associated with this setting, how it's stored, or
 *   how it's represented in the external configuration file.  This means
 *   that each subclass has to provide the property or properties that
 *   store the item's value, and must also define the methods that operate
 *   on the value.
 *   
 *   If you want to force a particular default setting for a particular
 *   preference item, overriding the setting stored in the global
 *   preferences file, you can override that SettingsItem's
 *   settingFromText() method.  This is the method that interprets the
 *   information in the preferences file, so if you want to ignore the
 *   preferences file setting, override this method to set the hard-coded
 *   value of your choosing.  
 */
class SettingsItem: object
    /*
     *   The setting's identifier string.  This is the ID of the setting as
     *   it appears in the external configuration file.
     *   
     *   The ID should be chosen to ensure uniqueness.  To reduce the
     *   chances of name collisions, we suggest a convention of using a two
     *   part name: a prefix identifying the source of the name (an
     *   abbreviated version of the name of the library, library extension,
     *   or game), followed by a period as a separator, followed by a short
     *   descriptive name for the variable.  The library follows this
     *   convention by using names of the form "adv3.xxx" - the "adv3"
     *   prefix indicates the standard library.
     *   
     *   The ID should contain only letters, numbers, and periods.  Don't
     *   use spaces or punctuation marks (other than periods).
     *   
     *   Note that the ID string is for the program's use, not the
     *   player's, so this isn't something we translate to different
     *   languages.  Note, though, that the configuration file is a simple
     *   text file, so it wouldn't hurt to use a reasonably meaningful
     *   name, in case the user takes it upon herself to look at the
     *   contents of the file.  
     */
    settingID = ''

    /* 
     *   Display a message fragment that shows the current setting value.
     *   We use this to show the player exactly what we're saving or
     *   restoring in response to a SAVE DEFAULTS or RESTORE DEFAULTS
     *   command, so that there's no confusion about which settings are
     *   included.  In most cases, the best thing to show here is the
     *   command that selects the current setting: "NOTIFY ON," for
     *   example.  This is for the UI's convenience; it's not used by the
     *   settings manager itself.  
     */
    settingDesc = ""

    /* 
     *   Get the textual representation of the setting - returns a string
     *   representing the setting as it should appear in the external
     *   configuration file.  We use this to write the setting to the file.
     */
    settingToText() { /* subclasses must override */ }

    /* 
     *   Set the current value to the contents of the given string.  The
     *   string contains a textual representation of a setting value, as
     *   previously generated with settingToText().  
     */
    settingFromText(str) { /* subclasses must override */ }

    /* 
     *   My "factory default" setting.  At pre-init time, before we've
     *   loaded the settings file for the first time, we'll run through all
     *   SettingsItems and store their pre-defined source-code settings
     *   here, as though we were saving the values to a file.  Later, when
     *   we load a file, if we find the file lacks an entry for this
     *   setting item, we'll simply re-load the factory default from this
     *   property. 
     */
    factoryDefault = nil
;

/*
 *   A binary settings item - this is for variables that have simple
 *   true/nil values. 
 */
class BinarySettingsItem: SettingsItem
    /* convert to text - use ON or OFF as the representation */
    settingToText() { return isOn ? 'on' : 'off'; }

    /* parse text */
    settingFromText(str)
    {
        /* convert to lower-case and strip off spaces */
        if (rexMatch('<space>*(<alpha>+)', str.toLower()) != nil)
            str = rexGroup(1)[3];

        /* get the new setting */
        isOn = (str.toLower() == 'on');
    }

    /* our value is true (on) or nil (off) */
    isOn = nil
;


/* ------------------------------------------------------------------------ */
/*
 *   The settings manager.  This object gathers up some global methods for
 *   managing the saved settings.  This base class provides only a
 *   programmatic interface - it doesn't have a user interface.  
 */
settingsManager: object
    /*
     *   Save the current settings.  This writes out the current settings
     *   to the global settings file.  On any error, the method throws an
     *   exception:
     *   
     *   - FileCreationException indicates that the settings file couldn't
     *   be opened for writing.  
     */
    saveSettings()
    {
        local s;
        
        /* retrieve the current settings */
        s = retrieveSettings();

        /* if that failed, there's nothing more we can do */
        if (s == nil)
            return;

        /* 
         *   Update the file's contents with all of the current in-memory
         *   settings objects. 
         */
        forEachInstance(SettingsItem, {item: s.saveItem(item)});

        /* write out the settings */
        storeSettings(s);
    }

    /* 
     *   Restore all of the settings.  If an error occurs, we'll throw an
     *   exception:
     *   
     *   - SettingsNotSupportedException - this is an older interpreter
     *   that doesn't support the "special files" feature, so we can't save
     *   or restore the default settings.  
     */
    restoreSettings()
    {
        local s;
        
        /* retrieve the current settings */
        s = retrieveSettings();

        /* 
         *   update all of the in-memory settings objects with the values
         *   from the file 
         */
        forEachInstance(SettingsItem, {item: s.restoreItem(item)});
    }

    /* 
     *   Retrieve the settings from the global settings file.  This returns
     *   a SettingsFileData object that describes the file's contents.
     *   Note that if there simply isn't an existing settings file, we'll
     *   successfully return a SettingsFileData object with no data - the
     *   absence of a settings file isn't an error, but is merely
     *   equivalent to an empty settings file.  
     */
    retrieveSettings()
    {
        local f;
        local s = new SettingsFileData();
        local linePat = new RexPattern(
            '<space>*(<alphanum|.>+)<space>*=<space>*([^\n]*)\n?$');
        
        /* 
         *   Try opening the settings file.  Older interpreters don't
         *   support the "special files" feature; if the interpreter
         *   predates special file support, it'll throw a "string value
         *   required," since it won't recognize the special file ID value
         *   as a valid filename.  
         */
        try
        {
            /* open the "library defaults" special file */
            f = File.openTextFile(LibraryDefaultsFile, FileAccessRead);
        }
        catch (FileNotFoundException fnf)
        {
            /* 
             *   The interpreter supports the special file, but the file
             *   doesn't seem to exist.  Simply return the empty file
             *   contents object. 
             */
            return s;
        }
        catch (RuntimeError rte)
        {
            /* 
             *   if the error is "string value required," then we have an
             *   older interpreter that doesn't support special files -
             *   indicate this by returning nil 
             */
            if (rte.errno_ == 2019)
            {
                /* re-throw this as a SettingsNotSupportedException */
                throw new SettingsNotSupportedException();
            }

            /* other exceptions are unexpected, so re-throw them */
            throw rte;
        }

        /* read the file */
        for (;;)
        {
            local l;
            
            /* read the next line */
            l = f.readFile();

            /* stop if we've reached end of file */
            if (l == nil)
                break;

            /* parse the line */
            if (rexMatch(linePat, l) != nil)
            {
                /* 
                 *   it parsed - add the variable and its value to the
                 *   contents object 
                 */
                s.addItem(rexGroup(1)[3], rexGroup(2)[3]);
            }
            else
            {
                /* it doesn't parse, so just keep the line as a comment */
                s.addComment(l);
            }
        }

        /* done with the file - close it */
        f.closeFile();

        /* return the populated file contents object */
        return s;
    }

    /* store the given SettingsFileData to the global settings file */
    storeSettings(s)
    {
        local f;
        
        /* 
         *   Open the "library defaults" file.  Note that we don't have to
         *   worry here about the old-interpreter situation that we handle
         *   in retrieveSettings() - if the interpreter doesn't support
         *   special files, we won't ever get this far, because we always
         *   have to retrieve the current file's contents before we can
         *   store the new contents.  
         */
        f = File.openTextFile(LibraryDefaultsFile, FileAccessWrite);

        /* write each line of the file's contents */
        foreach (local item in s.lst_)
            item.writeToFile(f);

        /* done with the file - close it */
        f.closeFile();
    }
;

/* ------------------------------------------------------------------------ */
/*
 *   Exception: the settings file mechanism isn't supported on this
 *   interpreter.  This indicates that this is an older interpreter that
 *   doesn't support the "special files" feature, so we can't save or load
 *   the global settings file. 
 */
class SettingsNotSupportedException: Exception
;

/* ------------------------------------------------------------------------ */
/*
 *   SettingsFileData - this is an object we use to represent the contents
 *   of the configuration file. 
 */
class SettingsFileData: object
    construct()
    {
        /* 
         *   We store the contents of the file in two ways: as a list, in
         *   the same order in which the contents appear in the file; and
         *   as a lookup table keyed by variable name.  The list lets us
         *   preserve the parts of the file's contents that we don't need
         *   to change when we read it in and write it back out.  The
         *   lookup table makes it easy to look up particular variable
         *   values.  
         */
        tab_ = new LookupTable(16, 32);
        lst_ = new Vector(16);
    }

    /* add a variable */
    addItem(id, val)
    {
        local item;
        
        /* create the item descriptor object */
        item = new SettingsFileItem(id, val);

        /* append it to our file-contents-ordered list */
        lst_.append(item);

        /* add it to the lookup table, keyed by the variable ID */
        tab_[id] = item;
    }

    /* add a comment line */
    addComment(str)
    {
        /* append a comment descriptor to the contents list */
        lst_.append(new SettingsFileComment(str));
    }

    /*
     *   Save an item.  This takes the current value from the given
     *   SettingsItem, and saves it to the in-memory representation of the
     *   file.  
     */
    saveItem(memItem)
    {
        local id;
        local val;
        local fileItem;

        /* get the item's ID */
        id = memItem.settingID;

        /* get the string representation of the item's value */
        val = memItem.settingToText();
        
        /* 
         *   look for a SettingsFileItem with the ID of the memory item
         *   we're saving 
         */
        fileItem = tab_[id];

        /* 
         *   If the file item exists, update its value with the value from
         *   the in-memory item.  Otherwise, simply add a new file item
         *   with the given ID and value. 
         */
        if (fileItem != nil)
        {
            /* 
             *   this variable was already in the file, so update it with
             *   the new value 
             */
            fileItem.val_ = val;
        }
        else
        {
            /* this variable wasn't previously in the file, so add it */
            addItem(id, val);
        }
    }

    /*
     *   Restore an item.  We'll look for a value for the given item in the
     *   file contents.  If we find the file item, we'll restore its value
     *   to the in-memory item.  If we don't find the file item, we'll
     *   restore the factory default.  
     */
    restoreItem(memItem)
    {
        local fileItem;
        
        /* look up the file item by ID */
        fileItem = tab_[memItem.settingID];

        /* 
         *   if this item appears in the file, restore its value; if not,
         *   restore it to its factory default setting 
         */
        memItem.settingFromText(fileItem != nil
                                ? fileItem.val_
                                : memItem.factoryDefault);
    }

    /* lookup table of values, keyed by variable name */
    tab_ = nil

    /* a list of SettingsFileItem objects giving the contents of the file */
    lst_ = nil
;

/*
 *   SettingsFileItem - this object describes a single item within an
 *   external settings file. 
 */
class SettingsFileItem: object
    construct(id, val)
    {
        id_ = id;
        val_ = val;
    }

    /* write this value to a file */
    writeToFile(f) { f.writeFile(id_ + ' = ' + val_ + '\n'); }

    /* the variable's ID */
    id_ = nil

    /* the string representation of the value */
    val_ = nil
;

/*
 *   SettingsFileComment - this object describes an unparsed line in the
 *   settings file.  We treat lines that don't match our parsing rules as
 *   comments.  We preserve the contents and order of these lines, but we
 *   don't otherwise try to interpret them. 
 */
class SettingsFileComment: object
    construct(str)
    {
        /* if it doesn't end in a newline, add a newline */
        if (!str.endsWith('\n'))
            str += '\n';

        /* remember the string */
        str_ = str;
    }

    /* write the comment line to a file */
    writeToFile(f) { f.writeFile(str_); }

    /* the text from the file */
    str_ = nil
;


