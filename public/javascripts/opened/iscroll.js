/*
 * jQuery iscroll Plugin
 * version: 1.0 (25-Jun-2009)
 * Copyright (c) 2010 - Tcha-Tcho (based on dragscrollable)
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */
(function($){ // secure $ jQuery alias

/**
 * Adds the ability to manage elements scroll by dragging
 * one or more of its descendant elements. Options parameter
 * allow to specifically select which inner elements will
 * respond to the drag events.
 * 
 * options properties:
 * ------------------------------------------------------------------------		
 *  dragSelector         | jquery selector to apply to each wrapped element 
 *                       | to find which will be the dragging elements. 
 *                       | Defaults to '>:first' which is the first child of 
 *                       | scrollable element
 * ------------------------------------------------------------------------		
 *  acceptPropagatedEvent| Will the dragging element accept propagated 
 *	                     | events? default is yes, a propagated mouse event 
 *	                     | on a inner element will be accepted and processed.
 *	                     | If set to false, only events originated on the
 *	                     | draggable elements will be processed.
 * ------------------------------------------------------------------------
 *  preventDefault       | Prevents the event to propagate further effectivey
 *                       | dissabling other default actions. Defaults to true
 * ------------------------------------------------------------------------
 *  
 *  usage examples:
 *
 *  To add the scroll by drag to the element id=viewport when dragging its 
 *  first child accepting any propagated events
 *	$('#viewport').iscroll(); 
 *
 *  To add the scroll by drag ability to any element div of class viewport
 *  when dragging its first descendant of class dragMe responding only to
 *  evcents originated on the '.dragMe' elements.
 *	$('div.viewport').iscroll({dragSelector:'.dragMe:first',
 *									  acceptPropagatedEvent: false});
 *
 *  Notice that some 'viewports' could be nested within others but events
 *  would not interfere as acceptPropagatedEvent is set to false.
 *		
 */
	// add easing - from oversroll
	jQuery.extend( jQuery.easing, {
		cubicEaseOut:function(p, n, firstNum, diff) {
			var c = firstNum + diff;
			return c*((p=p/1-1)*p*p + 1) + firstNum;
		}
	});
$.fn.iscroll = function( options ){

	var settings = $.extend(
		{   
			dragSelector:'>:first',
			acceptPropagatedEvent: true,
            preventDefault: true,
			friction: 15,
			smothness: 500,
			scrollType: 'iscroll',
			barColor: 'black',
			wheelSensitivity: 50,
			barDistance: 5,
			limitScroll: 250,
			firstAnimation: true
		},options || {});
		
		var delta = {left: null, top: null};
		var time;
	var iscroll= {
		mouseDownHandler : function(event) {
			// mousedown, left click, check propagation
			if (event.which!=1 ||
				(!event.data.acceptPropagatedEvent && event.target != this)){ 
				return false; 
			}
			event.data.scrollable.stop();//stop animations
			//let user to click in "inputables"
			var tag = "<" + event.target.tagName.toLowerCase() + ">";
				if ( (/<input>|<textarea>|<select>|<a>/).test(tag) ) return true;//oversroll
			// Initial coordinates will be the last when dragging
			event.data.lastCoord = {left: event.clientX, top: event.clientY}; 
			//bindings
			$.event.add( document, "mouseup", 
						 iscroll.mouseUpHandler, event.data );
			$.event.add( document, "mousemove", 
						 iscroll.mouseMoveHandler, event.data );
						
			if (event.data.preventDefault) {
                event.preventDefault();
                return false;
            }
		},
		mouseEnterHandler : function(event) { // User is over
			//make bars appears
			event.data.scrollable.find("#ibartop").fadeTo(200, 0.30);
			event.data.scrollable.find("#ibarleft").fadeTo(200, 0.30);
			
			event.data.scrollable.mousewheel(function(e, deltawheel) {
				var top = event.data.scrollable.scrollTop() - (deltawheel*event.data.wheelSensitivity);
				event.data.scrollable.scrollTop(top);
			});
						
			if (event.data.preventDefault) {
				event.preventDefault();
				return false;
			}
		},
		mouseLeaveHandler : function(event) { // User is over
			event.data.scrollable.find("#ibartop").fadeTo(200, 0.05);
			event.data.scrollable.find("#ibarleft").fadeTo(200, 0.05);
			event.data.scrollable.unmousewheel();
			if (event.data.preventDefault) {
				event.preventDefault();
				return false;
			}
		},
		scrollHandler : function(event) { // On scrolling
			var scrolltop = event.data.scrollable.attr("scrollTop");
			var top = scrolltop + scrolltop/(event.data.scrollable.height()/event.data.bartop.height());
			event.data.bartop.css({top: Math.round(top)-10});
		},
		mouseMoveHandler : function(event) { // User is dragging
			// How much did the mouse move?
			delta = {left: (event.clientX - event.data.lastCoord.left),
					 top: (event.clientY - event.data.lastCoord.top)};
			// Set the scroll position relative to what ever the scroll is now
			event.data.scrollable.scrollLeft(
							event.data.scrollable.scrollLeft() - delta.left);
			event.data.scrollable.scrollTop(
							event.data.scrollable.scrollTop() - delta.top);
			// Save where the cursor is
			event.data.lastCoord={left: event.clientX, top: event.clientY}
			
			if (event.data.preventDefault) {
                event.preventDefault();
                return false;
            }

		},
		mouseUpHandler : function(event) { // Stop scrolling
			$.event.remove( document, "mousemove", iscroll.mouseMoveHandler);
			$.event.remove( document, "mouseup", iscroll.mouseUpHandler);
		
			//calculate velocity and friction
			var top = (event.data.scrollable.scrollTop() - (delta.top * event.data.friction));
			var left = (event.data.scrollable.scrollLeft() - (delta.left * event.data.friction));
			time = event.data.smothness + Math.abs(((delta.top + delta.left)/2)*30);

			//expose if is scrolling
			if (event.data.scrollable.scrollTop() > top || event.data.scrollable.scrollTop() < top ) {
				$.fn.iscroll.scrolling = true;
			} else {
				$.fn.iscroll.scrolling = false;
			}

			//apply pos dragging
			event.data.scrollable.animate({ scrollLeft: left,scrollTop: top}, time)
			
			//prevent stupid movements
			delta.top = null;
			delta.left = null;
					
			if (event.data.preventDefault) {
               event.preventDefault();
               return false;
            }
		}		
	}	
	// set up the initial events
	this.each(function() {
		// closure object data for each scrollable element
		var data = {scrollable : $(this),
					acceptPropagatedEvent : settings.acceptPropagatedEvent,
                    preventDefault : settings.preventDefault,
					smothness : settings.smothness,
					friction : settings.friction,
					dragSelector : $(this).find(settings.dragSelector),
					wheelSensitivity : settings.wheelSensitivity
					}

		//show to user that he can slide
		if (settings.firstAnimation == true){
			data.scrollable.animate({ scrollTop: 100 }, 500, function(){data.scrollable.animate({ scrollTop: 0 }, 800,'cubicEaseOut')});
		};
		
		//remove previous ibar
		data.scrollable.children().remove("#ibartop");

		//setup scrollbar
		if (settings.scrollType == "iscroll"){
			data.scrollable.css({overflow:'hidden',position:'relative'})			
		
			//test if all images have loaded to get the exact size
			var images_loaded = 0;
			var elems = data.scrollable.find("img");
			var all_images = elems.length;
			  elems.bind('load',function(){
			      test_all_images()//initiate the handler
			  }).each(function(){
			      // cached images don't fire load sometimes, so we reset src.
			      if ($(this).complete || $(this).complete === undefined){ $(this).src = $(this).src; }
			  });
		  	function test_all_images(){
				images_loaded ++;
				if (all_images == images_loaded) {
					bind_iscroll();
				}
			}
			function bind_iscroll() {
				elems.unbind('load');
				if (data.scrollable[0].scrollHeight > data.scrollable.height()){
					//prepare scroll bars
					data.bartop = $("<div id='ibartop' style='background: "+ settings.barColor +";position: absolute;width: 2px;z-index: 30;'></div>");
					data.bartop.height(data.scrollable.height() / (data.scrollable[0].scrollHeight / data.scrollable.height()))
						  .css({left: settings.barDistance})
						  .fadeTo("fast", 0.10)
						  .css({top: 0});
					data.scrollable.append(data.bartop);
					data.scrollable.bind('scroll', data, iscroll.scrollHandler);
					data.scrollable.bind('mouseenter', data, iscroll.mouseEnterHandler);
					data.scrollable.bind('mouseleave', data, iscroll.mouseLeaveHandler);
				}
			}
			
		} else if (settings.scrollType == 'hidden') {
			data.scrollable.css({overflow:'hidden',position:'relative'});
			/*
				TODO : enable mouse wheel here
			*/
		} else {
			//Use normal OS bars
			data.scrollable.css({overflow:'auto',position:'relative'});
		}

		// Set mouse initiating event on the desired descendant
		data.dragSelector.bind('mousedown', data, iscroll.mouseDownHandler);
	});
	return this;
}; //end plugin iscroll
$.fn.iscroll.scrolling = false;
})( jQuery ); // confine scope