/*
** Standings.js - javascript support for the PAC Swimmer Age Group Standings web pages
**  (bob upshaw)
**
*/

// these three variables are used to manage a small area at the bottom of the web page
// that shows how much memory we're using.
var OriginalPageSize = 0;		// size of "master" page when originally served
var PreviousPageSize = 0;		// size of the web page prior to loading a "virtual" page
var CurrentPageSize = 0;		// size of the web page after loading a "virtual" page
var ShowDetails = false;		// 
/*
** Invoked to open or close some details of a swimmer.
** passedID is the id of the row we are opening/closing.
** return false.
*/
function ponclick( passedID ) {
	var result = false;
	// just show or hide some existing DOM:
	var mydisplay = document.all[passedID].style.display;
	if( mydisplay == "none" ) {
		mydisplay = "";
	} else {
		mydisplay = "none";
	}
	document.all[passedID].style.display=mydisplay;
	return result;
} // end of ponclick()


function ponclick_details( passedID ) {
	var result = false;
	if( ShowDetails ) {
		// just show or hide some existing DOM:
		var mydisplay = document.all[passedID].style.display;
		if( mydisplay == "none" ) {
			mydisplay = "";
		} else {
			mydisplay = "none";
		}
		document.all[passedID].style.display=mydisplay;
	}
	return result;
} // end of ponclick_details()



/*
** Invoked to open or close a swimmer, expanding the containing section if not currently expanded.
** passedID is the id of the swimmer we are opening.  If it's not an id of something in the current
** DOM then we have to go get the missing content.
** genAgeGroupFileName indicates the name of the file containing the section, and is
**	of the form 'F-18-24' or 'M-50-54'.
** Return true if we opened a swimmer, which means that the swimmer's section
** may have to be expanded and the "(Click here to collapse this section)" phrase
** shown.  If it turns out that the section is already expanded and the phrase
** is already shown it doesn't hurt to do it again.
** Return false if we had to go get content prior to opening a swimmer or we closed a swimmer 
** (which means the swimmer's section is NOT hidden.)
*
* document HTMLVSupportDir - directory from which we'll read the virtual files at runtime
*/
function OpenSwimmer( HTMLVSupportDir, passedID, genAgeGroupFileName ) {
	var result;
	// first of all, is the passed ID defined?
	if( (passedID != "") && document.getElementById( passedID ) !== null ) {
		// The swimmer we are going to open has already been loaded, which means their entire
		// section has been loaded, so in this 
		// case we just show or hide some existing DOM:
		var mydisplay = document.all[passedID].style.display;
		if( mydisplay == "none" ) {
			mydisplay = "";
			result = true;
		} else {
			mydisplay = "none";
			result = false;
		}
		document.all[passedID].style.display=mydisplay;
	} else { // In this case we need to go get the missing content
		PreviousPageSize = $("#MainContentDiv").html().length;
		var virtSectionId = genAgeGroupFileName + "-GenAgeDiv";
		var remoteFile = HTMLVSupportDir + "/" + genAgeGroupFileName + ".html";
		$("#"+virtSectionId).load( remoteFile, function() {
			if( passedID != "" ) {
				document.all[passedID].style.display="";
			}
			// Since we are now showing a full section will will also
			// show the "(Click here to collapse this section)" phrase
			var genAgeGroup = genAgeGroupFileName;
			genAgeGroup = genAgeGroup.replace( '-', ':' );
			document.all[genAgeGroup+'-Collapse'].style.display="";

			// since we've loaded some new content we will now recompute the display
			// our current page size
			CurrentPageSize = $("#MainContentDiv").html().length;
			var diff = CurrentPageSize - PreviousPageSize;
			$("#pageStats").html(	"Original Page Size: " + OriginalPageSize + " / " + 
									"Previous Page Size: " + PreviousPageSize + " / " +  
									"Current Page Size: "  + CurrentPageSize + 
									" (" + "Difference: " + diff + ")" );
		}  // end of anonymous function
		);  // end of load
		result = false;
	}  // end of "In this case we ..."
	return result;
} // end of OpenSwimmer()





/*
** Expand an age group section.  This function is called with an indicator of which 
** section to expand.  It's assumed that all the content for the section has already
** been loaded (via Ajax in OpenSwimmer()) but is hidden.  This function will show
** that content and also show the "collapse this section" phrase and hide the 
** "see the rest" phrase.  If the section is already expanded this function
** won't do any harm (but also won't do anything useful.)
*/
function ExpandSection( genAgeGrp ) {
	// genAgeGrp is of the form 'F:18-24'
	var passedClass = genAgeGrp + "-Collapse";
	var elements;
	
	// First, we don't try to expand a section that contains 10 or less swimmers.  We know that by 
	// looking at the id of the <tr> containing the "Click here to see the rest of the swimmers"
	// phrase.  If it's not 'genAgeGrp + "-MoreThan10"' then this section has less than 11 swimmers
	// so we don't expand anything.
	if( document.getElementById( genAgeGrp + "-MoreThan10" ) !== null ) {
		// this section contains more than 10 swimmers
		// Before we expand this section we will hide the "Click here to see the rest of the swimmers"
		// phrase
		document.all[genAgeGrp + "-MoreThan10"].style.display="none";
		// Also, before we expand this section will will show the "(Click here to collapse this section)"
		// phrase
		document.all[passedClass].style.display="";

		// now expand the section by showing all swimmers 11th and above
		elements = document.getElementsByClassName(passedClass)
		for (var i = 0; i < elements.length; i++){
			elements[i].style.display = "";
		}
	} else {
		// HOWEVER, no matter what, if asked to expand the section we will show the 
		// "(Click here to collapse this section)" phrase.
		document.all[passedClass].style.display="";
	}
	return false;
} // end of ExpandSection()



/*
** Collapse an age group section.  This function is called with an indicator of which 
** section to collapse.  It's assumed that all the content for the section has already
** been loaded (via Ajax in OpenSwimmer()) and is visible, possibly with some open swimmers.  
** This function will hide all but the top 10 swimmers, and also hide the
** "collapse this section" phrase and show the "see the rest" phrase.  
** If the section is already collapsed this function
** won't do any harm (but also won't do anything useful.)
*/
function CollapseSection( genAgeGrp ) {
	// genAgeGrp is of the form 'F:18-24'
	var passedClass = genAgeGrp + "-Collapse";
	var elements;
	
	// Before we collapse this section we will close all the open swimmers.  
	// We want to close all blocks in the class of the form 'F:18-24-DisplayToggle'
	elements = document.getElementsByClassName(genAgeGrp + "-DisplayToggle");
	for (var i = 0; i < elements.length; i++){
		elements[i].style.display = "none";
	}
	// Also, before we collapse this section we will make the "Click here to see the rest of the swimmers"
	// phrase visible (thus active)
	if( document.getElementById( genAgeGrp + "-MoreThan10" ) !== null ) {
		document.all[genAgeGrp + "-MoreThan10"].style.display="";
	}
	// now collapse the section by hiding all swimmers 11th and above
	elements = document.getElementsByClassName(passedClass)
	for (var i = 0; i < elements.length; i++){
		elements[i].style.display = "none";
	}		
	// hide the "(Click here to collapse this section)" phrase
	document.all[passedClass].style.display="none";
	return false;
} // end of CollapseSection()


/*
** Now something controversial!
** We're going to use the following function to determine whether or not the request is coming from
** a "mobile" device or not.  Yeah, I know.  This isn't right.  Nothing's "right", but this is
** quick and dirty.  At the moment we're really only interested in knowing whether or not the device
** viewing our page is a small screen or not.  Completely different question, but this will work for now.
** (If you want to know what the controversy is then Google it.  Follow all the links and then come back
** in a few months.)
*/
function isMobile() {
	var index = navigator.appVersion.indexOf("Mobile");
	return (index > -1);
} // end of isMobile()


/*
** getQueryVariable - return the value of the query variable requested.  For example, if the request looks like this:
**		file:///Users/bobup/Documents/workspace/TopTen-2016/standings.html?open=W_45_49_1_237
** Calling     getQueryVariable("open") returns "W_45_49_1_237"
**		file:///Users/bobup/Documents/workspace/TopTen-2016/standings.html
** Calling     getQueryVariable("open") returns ""
*/
function getQueryVariable(variable) {
       var query = window.location.search.substring(1);
       var vars = query.split("&");
       for (var i=0;i<vars.length;i++) {
		   var pair = vars[i].split("=");
		   if(pair[0] == variable){ return pair[1]; }
       }
       return(false);
}

/*
** This function implements the "Jump to Gender and Age Group of interest" controls near
** the top of the page.
*/
function jumpButtonClick() {
	var gender=document.getElementById("gender").value;
	var agegroup=document.getElementById("agegroup").value;
	location.hash = "#" + gender + "-" + agegroup + "-GenAgeDiv";
}




/*
** this code will run when the page is first served and send the user to the location
** requested in the 'open' query variable.  
*/
$(document).ready(function() {
	var val = getQueryVariable( "open" );
	if( val != "" ) {
		ponclick( val );
		window.location.hash = val + "-head";
		// the following fixes a bug in floatThread
		window.scrollTo(window.scrollX, window.scrollY - 40);
	}
});



// floating header on the page
$(document).ready(function() {
	/*
	* jQuery.floatThead - see http://mkoryak.github.io/floatThead/ for this good work by
	*	Misha Koryak.
	*/
	// we don't show the floating header on a phone
	if( ! isMobile() ) {
		$('table.Category').floatThead( {
			useAbsolutePositioning: false
		});
	}
});

// Used to initialize the metrics shown when the logo at the bottom of the page is clicked.
$(document).ready(function() {
	OriginalPageSize = $("#MainContentDiv").html().length;
	$("#pageStats").html(	"Original Page Size: " + OriginalPageSize );
});

// change display of Jump button if necessary
$(document).ready(function() {
	if( isMobile() ) {
		var theDiv = document.querySelector("#jump");
		theDiv.classList.remove("jumpArea");
		theDiv.classList.add("jumpArea_mobile");
		var theGender = document.querySelector("#gender");
		theGender.classList.remove("selectClass");
		theGender.classList.add("selectClass_mobile");
		var theAgeGroup = document.querySelector("#agegroup");
		theAgeGroup.classList.remove("selectClass");
		theAgeGroup.classList.add("selectClass_mobile");
		var theButton = document.querySelector("#jumpButton");
		theButton.classList.remove("buttonClass");
		theButton.classList.add("buttonClass_mobile");
	}
});


//document HTMLVSupportDir - directory from which we'll read the virtual files at runtime
function ShowSoty(event, HTMLVSupportDir) {
	// if this click is accompanied by both the shift key and the option (Mac) or alt (Win) key down
	// then we will handle this in a special way
	if( (event.shiftKey) && ((event.altKey) || (event.metaKey)) ) {
		// just show or hide some existing DOM:
		var mydisplay = document.all['details'].style.display;
		if( mydisplay == "none" ) {
			// we need to show details....
			var r = confirm( "Show Details?" );
			if( r ) {
				ShowDetails =  true;
				mydisplay = "";
				var remoteFile = HTMLVSupportDir + "/soty.html";
				$("#soty").load( remoteFile, function() {
				}  // end of anonymous function
				);  // end of load()
				ponclick('pageStats');
			} else {
				ShowDetails = false;
			}
		} else {
			// we need to hide the details
			mydisplay = "none";
			ShowDetails = false;
			document.all['pageStats'].style.display=mydisplay;
		}
		document.all['details'].style.display=mydisplay;
	} else {
		// this is not a special click - a click on the logo just sends the user to the pms web site
		window.location.href="http://pacificmasters.org/";
	}
} // end of ShowSoty()


// ShowSotyClick - same idea as ShowSoty() except when called it will always toggle the state
// of the SOTY section regardless of the state of the keyboard.  Used on phones, etc.
function ShowSotyClick(event, HTMLVSupportDir) {
	var mydisplay = document.all['details'].style.display;
	if( mydisplay == "none" ) {
		// we need to show details....
		var r = confirm( "Show Details?" );
		if( r ) {
			ShowDetails =  true;
			mydisplay = "";
			var remoteFile = HTMLVSupportDir + "/soty.html";
			$("#soty").load( remoteFile, function() {
			}  // end of anonymous function
			);  // end of load()
			ponclick('pageStats');
		} else {
			ShowDetails = false;
		}
	} else {
		// we need to hide the details
		mydisplay = "none";
		ShowDetails = false;
		document.all['pageStats'].style.display=mydisplay;
	}
	document.all['details'].style.display=mydisplay;
} // end of ShowSotyClick()




// ShowStats - show statistics generated when top ten page was generated
function ShowStats( event, statFile ) {

	$("#numericStats").load( statFile, function( response, status, xhr ) {
		if( status == "error" ) {
			var msg = "Unable to find the statistics!  ";
			$("#numericStats").html( msg + xhr.status + ": " + xhr.statusText );
		}
	}  // end of anonymous function
	);  // end of load()
	document.getElementById("StatsButton").style.display="none";
	
} // end of ShowStats()


/*
 * There is a "bug" in ios6 (and beyond?) where apple caches ajax requests even if the
 * responses would be different for the same request.  To prevent this we're going
 * to disable caching for all POSTs.
 */
$.ajaxSetup({
    type: 'POST',
    headers: { "cache-control": "no-cache" }
});

