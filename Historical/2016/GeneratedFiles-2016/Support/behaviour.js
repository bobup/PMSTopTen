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

/*
   Behaviour v1.1 by Ben Nolan, June 2005. Based largely on the work
   of Simon Willison (see comments by Simon below).

   Description:

   	Uses css selectors to apply javascript behaviours to enable
   	unobtrusive javascript in html documents.

   Usage:

	var myrules = {
		'b.someclass' : function(element){
			element.onclick = function(){
				alert(this.innerHTML);
			}
		},
		'#someid u' : function(element){
			element.onmouseover = function(){
				this.innerHTML = "BLAH!";
			}
		}
	};

	Behaviour.register(myrules);

	// Call Behaviour.apply() to re-apply the rules (if you
	// update the dom, etc).

   License:

   	My stuff is BSD licensed. Not sure about Simon's.

   More information:

   	http://ripcord.co.nz/behaviour/

*/

//////////////// Start of presence check ///////////////
if(typeof Behaviour=='undefined') {

var Behaviour = {
	list : new Array,

	register : function(sheet){
		Behaviour.list.push(sheet);
	},

	start : function(){
		Behaviour.addLoadEvent(function(){
			// quit if this function has already been called
			if (arguments.callee.done) return;
			arguments.callee.done = true;

			Behaviour.apply();
		});
	},

	apply : function(){

		var h, i, sheet, selector, list, element;
		for (h=0; sheet=Behaviour.list[h];h++){
			for (selector in sheet){
				list = document.getElementsBySelector(selector);

				if (!list){
					continue;
				}

				for (i=0;element=list[i];i++){
					sheet[selector](element);
				}
			}
		}
	},

	addLoadEvent : function(func){
		if (window.addEventListener) {
			var load = function() {
				if (arguments.callee.done)
					return;
				arguments.callee.done = true;
				arguments.callee.func();
			}
			load.func = func;
			window.addEventListener("DOMContentLoaded", load, false);
			window.addEventListener("load", load, false);
		} else if (window.attachEvent) {
			window.attachEvent('onload',func);
		} else {

			var oldonload = window.onload;

			if (typeof window.onload != 'function') {
				window.onload = func;
			} else {
				window.onload = function() {
					oldonload();
					func();
				}
			}
		}
	}
}

Behaviour.start();

/*
   The following code is Copyright (C) Simon Willison 2004.

   document.getElementsBySelector(selector)
   - returns an array of element objects from the current document
     matching the CSS selector. Selectors can contain element names,
     class names and ids and can be nested. For example:

       elements = document.getElementsBySelect('div#main p a.external')

     Will return an array of all 'a' elements with 'external' in their
     class attribute that are contained inside 'p' elements that are
     contained inside the 'div' element which has id="main"

   New in version 0.4: Support for CSS2 and CSS3 attribute selectors:
   See http://www.w3.org/TR/css3-selectors/#attribute-selectors

   Version 0.4 - Simon Willison, March 25th 2003
   -- Works in Phoenix 0.5, Mozilla 1.3, Opera 7, Internet Explorer 6, Internet Explorer 5 on Windows
   -- Opera 7 fails
*/

function getAllChildren(e) {
  // Returns all children of element. Workaround required for IE5/Windows. Ugh.
  return e.all ? e.all : e.getElementsByTagName('*');
}

document.getElementsBySelector = function(selector) {
  // Attempt to fail gracefully in lesser browsers
  if (!document.getElementsByTagName) {
    return new Array();
  }
  // Split selector in to tokens
  var token, bits, tagName, id, className, found, foundCount, elements, currentContextIndex, h, j, k;
  var tokens = selector.split(' ');
  var currentContext = new Array(document);
  for (var i = 0; i < tokens.length; i++) {
    token = tokens[i].replace(/^\s+/,'').replace(/\s+$/,'');;
    if (token.indexOf('#') > -1) {
      // Token is an ID selector
      bits = token.split('#');
      tagName = bits[0];
      id = bits[1];
      element = document.getElementById(id);
      if (tagName && element.nodeName.toLowerCase() != tagName) {
        // tag with that ID not found, return false
        return new Array();
      }
      // Set currentContext to contain just this element
      currentContext = new Array(element);
      continue; // Skip to next token
    }
    if (token.indexOf('.') > -1) {
      // Token contains a class selector
      bits = token.split('.');
      tagName = bits[0];
      className = bits[1];
      if (!tagName) {
        tagName = '*';
      }
      // Get elements matching tag, filter them for class selector
      found = new Array;
      foundCount = 0;
      for (h = 0; h < currentContext.length; h++) {
        if (tagName == '*') {
            elements = getAllChildren(currentContext[h]);
        } else {
            elements = currentContext[h].getElementsByTagName(tagName);
        }
        for (j = 0; j < elements.length; j++) {
          found[foundCount++] = elements[j];
        }
      }
      currentContext = new Array;
      currentContextIndex = 0;
      for (k = 0; k < found.length; k++) {
        if (found[k].className && found[k].className.match(new RegExp('\\b'+className+'\\b'))) {
          currentContext[currentContextIndex++] = found[k];
        }
      }
      continue; // Skip to next token
    }
    // Code to deal with attribute selectors
    if (token.match(/^(\w*)\[(\w+)([=~\|\^\$\*]?)=?"?([^\]"]*)"?\]$/)) {
      tagName = RegExp.$1;
      var attrName = RegExp.$2;
      var attrOperator = RegExp.$3;
      var attrValue = RegExp.$4;
      if (!tagName) {
        tagName = '*';
      }
      // Grab all of the tagName elements within current context
      found = new Array;
      foundCount = 0;
      for (h = 0; h < currentContext.length; h++) {
        if (tagName == '*') {
            elements = getAllChildren(currentContext[h]);
        } else {
            elements = currentContext[h].getElementsByTagName(tagName);
        }
        for (j = 0; j < elements.length; j++) {
          found[foundCount++] = elements[j];
        }
      }
      currentContext = new Array;
      currentContextIndex = 0;
      var checkFunction; // This function will be used to filter the elements
      switch (attrOperator) {
        case '=': // Equality
          checkFunction = function(e) { return (e.getAttribute(attrName) == attrValue); };
          break;
        case '~': // Match one of spaces seperated words
          checkFunction = function(e) { return (e.getAttribute(attrName).match(new RegExp('\\b'+attrValue+'\\b'))); };
          break;
        case '|': // Match start with value followed by optional hyphen
          checkFunction = function(e) { return (e.getAttribute(attrName).match(new RegExp('^'+attrValue+'-?'))); };
          break;
        case '^': // Match starts with value
          checkFunction = function(e) { return (e.getAttribute(attrName).indexOf(attrValue) == 0); };
          break;
        case '$': // Match ends with value - fails with "Warning" in Opera 7
          checkFunction = function(e) { return (e.getAttribute(attrName).lastIndexOf(attrValue) == e.getAttribute(attrName).length - attrValue.length); };
          break;
        case '*': // Match ends with value
          checkFunction = function(e) { return (e.getAttribute(attrName).indexOf(attrValue) > -1); };
          break;
        default :
          // Just test for existence of attribute
          checkFunction = function(e) { return e.getAttribute(attrName); };
      }
      currentContext = new Array;
      currentContextIndex = 0;
      for (k = 0; k < found.length; k++) {
        if (checkFunction(found[k])) {
          currentContext[currentContextIndex++] = found[k];
        }
      }
      // alert('Attribute Selector: '+tagName+' '+attrName+' '+attrOperator+' '+attrValue);
      continue; // Skip to next token
    }

    if (!currentContext[0]){
    	return null;
    }

    // If we get here, token is JUST an element (not a class or ID selector)
    tagName = token;
    found = new Array;
    foundCount = 0;
    for (h = 0; h < currentContext.length; h++) {
      elements = currentContext[h].getElementsByTagName(tagName);
      for (j = 0; j < elements.length; j++) {
        found[foundCount++] = elements[j];
      }
    }
    currentContext = found;
  }
  return currentContext;
}

/* That revolting regular expression explained
/^(\w+)\[(\w+)([=~\|\^\$\*]?)=?"?([^\]"]*)"?\]$/
  \---/  \---/\-------------/    \-------/
    |      |         |               |
    |      |         |           The value
    |      |    ~,|,^,$,* or =
    |   Attribute
   Tag
*/

//////////// End of presence check /////////////
}