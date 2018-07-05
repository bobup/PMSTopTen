/*
 * Copyright (c) 2007, CustomWare Asia Pacific
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright notice,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of "CustomWare Asia Pacific" nor the names of its contributors
 *       may be used to endorse or promote products derived from this software
 *       without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * This script provides the code for {cloak} and {toggle-cloak}.
 *
 * It requires that Ben Nolan's 'Behaviour' library is installed.
 */

var Cloak = {

  // The HTML to insert into the toggle when clicking it will open the cloak.
  openHTML : "+",
  // The HTML to insert into the toggle when clicking it will close the cloak.
  closeHTML : "-",
  
  // If true, visitors can click on any part of the nearest 'block' ancestor to toggle.
  toggleZone : true,
  
  // The number of days to remember the visitor's last cloak settings
  memoryDuration : 0,
  
  // The prefix to place in front of the 
  memoryPrefix : window.location.pathname,
  
  memoryName : function() {
    return Cloak.memoryPrefix + ":cloakData";
  },
  
  // The path to remember the current settings within.
  memoryPath : "/",

  rootCloaks : new Array(),
  
  cloakAll : function(cascade) {
    for (var i = 0; i < this.rootCloaks.length; i++)
      this.rootCloaks[i].cloak(cascade);
  },
  
  uncloakAll : function(cascade) {
    for (var i = 0; i < this.rootCloaks.length; i++)
      this.rootCloaks[i].uncloak(cascade);
  },

  /**
   * Stores the cloak settings for later recall.
   */
  store : function() {
debug("store");
    if (Cloak.memoryDuration <= 0)
    {
      Memory.forgetValue(Cloak.memoryName(), Cloak.memoryPath);
      return;
    	}
    	
    	var expdate = new Date ();
	expdate.setTime(expdate.getTime() + (24 * 60 * 60 * 1000) * Cloak.memoryDuration );
    	
    var data = new Object();
    var cloaks = Cloak.allCloaks();
    
    for (var i = 0; i < cloaks.length; i++)
    {
      data[cloaks[i].id] = cloaks[i].isCloaked() ? "c" : "u";
    }
    
    Memory.storeMap(Cloak.memoryName(), data, expdate, Cloak.memoryPath);
  },
  
  recall : function() {
debug("recall");
    if (Cloak.memoryDuration <= 0)
    {
      Memory.forgetValue(Cloak.memoryName(), Cloak.memoryPath);
      return;
    	}

    var data = Memory.recallMap(Cloak.memoryName());
    
    for (id in data)
    {
      var cloak = document.getElementById(id);
      if (cloak)
      {
        if (data[id] == "c")
          cloak.cloak();
        else
          cloak.uncloak();
      }
    }
  },
  
  allCloaks : function() {
    var cloaks = new Array();
    for (var i = 0; i < Cloak.rootCloaks.length; i++)
    {
      this.addAllCloaks(cloaks, Cloak.rootCloaks[i]);
    }
    return cloaks;
  },
  
  // 'private'
  addAllCloaks : function(cloaks, cloak) {
    if (cloak)
    {
      cloaks.push(cloak);
      if (cloak.childCloaks)
        for (var i = 0; i < cloak.childCloaks.length; i++)
          this.addAllCloaks(cloaks, cloak.childCloaks[i]);
    }
  },
  
  // Finds the closest parent cloak for this cloak.
  // May return null if there is no surrounding cloak.
  findParentCloak : function(element) {
    var parent = element.parentNode;
    while (parent && !parent.isCloaked)
      parent = parent.parentNode;
    return parent;
  },
  
  // Finds the cloak for the specified toggle.
  findCloakForToggle : function(toggle) {
    if (!toggle.cloak) {
      // Get all values after the first 4 as the cloak id.
      var cloakId = toggle.id.substr(4);
      toggle.cloak = document.getElementById(cloakId);
    }
    return toggle.cloak;
  },
  
  _blockTagList : "|DIV|P|LI|TD|TH|PRE|BLOCKQUOTE|H1|H2|H3|H4|H5|H6|",
  
  findParentBlock : function(node) {

    while (node)
    {
      if (Cloak._blockTagList.indexOf('|'+node.tagName+'|') > 0)
      //if (Cloak._blockTagList.test(node.tagName))
        return node;
      node = node.parentNode;
    }
    return null;
  },
  
  // The Behaviour rules.
  rules : {
    
    'span.cloakExclusive' : function(toggle) {
debug("span.cloakToggle: id=" + toggle.id);
      toggle.exclusive = true;
    },
  
    'span.cloakToggle' : function(toggle) {
debug("span.cloakToggle: id=" + toggle.id);
      
      toggle.cloak = Cloak.findCloakForToggle(toggle);

      if (toggle.cloak)
      {
        if (!(toggle.cloak.toggles))
        {
          toggle.cloak.toggles = new Array();
        }
        toggle.cloak.toggles.push(toggle);
        
        toggle.doToggle = function() {
          if (this.cloak.isCloaked() && this.exclusive)
          {
            if (this.cloak.parentCloak)
              this.cloak.parentCloak.cloakChildren();
            else
              Cloak.cloakAll();
          }
            
          this.cloak.toggleCloak();
        };
        
        toggle.updateHTML = function() {
          if (this.cloak.isCloaked())
            this.innerHTML = Cloak.openHTML;
          else
            this.innerHTML = Cloak.closeHTML;
        };

        var block;
        if (Cloak.toggleZone) {
          block = Cloak.findParentBlock(toggle);
          if (block)
          {
            block.toggle = toggle;
            block.className += (block.className ? " " : "") + "cloakToggle";
            
            block.onclick = function() {
              this.toggle.doToggle();
            };
            
            block.onkeypress = function(event) {
              // Only toggle only on enter
              if (event.which == 13)
                this.toggle.doToggle();
            };
          }
        }
        
        if (!block) {
          // toggles 
          toggle.onclick = function() {
            this.doToggle();
          };
          
          toggle.onkeypress = function() {
            this.doToggle();
          };
        }
        
        // Initialisation
        toggle.innerHTML = Cloak.openHTML;
      }
    },
  
    'span.cloak' : function(cloak) {
debug("span.cloak: id=" + cloak.id);

      cloak.isCloaked = function() {
        return this.style.display == "none";
      };
      
      // Allows addition of children.
      cloak.addChildCloak = function(childCloak) {
        if (!this.childCloaks)
          this.childCloaks = new Array();
        this.childCloaks.push(childCloak);
      };
      
      /** 
       * Cloaks the section.
       * 
       * @param cascade if true, cloak all child cloak sections.
       */
      cloak.cloak = function(cascade) {
        this.style.display = "none";
        this.updateToggles();
        
        if (cascade)
          this.cloakChildren(cascade);

        if (this.parentBlock)
        {
          // This is a work-around for a weird rendering issue in Opera.
          var parentBlockDisplay = this.parentBlock.style.display;
          if (parentBlockDisplay != "none")
          {
	          this.parentBlock.style.display = "none";
	          this.parentBlock.style.display = parentBlockDisplay;
	      }
        }
      };
      
      /**
       * Cloaks any child cloaks this section may contain.
       */
      cloak.cloakChildren = function(cascade) {
        if (this.childCloaks)
        {
          for (var i = 0; i < this.childCloaks.length; i++)
            this.childCloaks[i].cloak(cascade);
        }
      };
      
      cloak.uncloak = function(cascade) {
        this.style.display = "";
        this.updateToggles();
        
        if (cascade)
          this.uncloakChildren(cascade);
      };
      
      cloak.uncloakChildren = function(cascade) {
        if (this.childCloaks)
        {
          for (var i = 0; i < this.childCloaks.length; i++)
            this.childCloaks.uncloak(cascade);
        }
      };
      
      cloak.updateToggles = function() {
        if (this.toggles)
        {
          for (var i = 0; i < this.toggles.length; i++)
          {
            this.toggles[i].updateHTML();
          }
        }
      }
      
      cloak.toggleCloak = function(cascade) {
        if (this.isCloaked())
        {
          this.uncloak(cascade);
        }
        else
        {
          this.cloak(cascade);
        }
      };

      cloak.parentCloak = Cloak.findParentCloak(cloak);
      
      if (document.browserInfo.isOpera) {
debug("span.cloak: applying Opera workaround");
	    cloak.parentBlock = Cloak.findParentBlock(cloak);
	  }

      // register the cloak for later.
      if (cloak.parentCloak)
        cloak.parentCloak.addChildCloak(cloak);
      else
        Cloak.rootCloaks.push(cloak);
      
      cloak.updateToggles();
    },
    
    'span.cloakHidden' : function(cloak) {
debug("span.cloakHidden: id=" + cloak.id);
      cloak.cloak();
    }
  }
};

Behaviour.register(Cloak.rules);

if (Memory) {
	Memory.addLoadEvent(Cloak.recall);
	Memory.addUnloadEvent(Cloak.store);
}
