var rules = {
    'a.popup' : function(el) {
        el.observe('click', function(event) {
            Krang.popup(this.readAttribute('href'));
            Event.stop(event);
        }.bindAsEventListener(el));
    },
    'a.help' : function(el) {
        // for now, just treat them like popup links
        // this may be expanded in the future
        el.observe('click', function(event) {
            Krang.popup(this.readAttribute('href'));
            Event.stop(event);
        }.bindAsEventListener(el));
    },
    'a.ajax' : function(el) {
        el.observe('click', function(event) {
            Krang.ajax_update({
                url       : this.href,
                div       : Krang.class_suffix(el, 'for_'),
                indicator : Krang.class_suffix(el, 'show_')
            });
            Event.stop(event);
        }.bindAsEventListener(el));
    },
    'form' : function(el) {
        // skip it if it has a class of 'non_ajax'
        if( el.hasClassName('non_ajax') ) return;

        // only continue if we don't have any inputs of type 'file'
        // since you can't send those vi AJAX
        for(var i=0; i < el.elements.length; i++) {
            var field = el.elements[i];
            if( field.type == 'file' ) return;
        }

        // save the old on submit if there is one so that we can
        // call it later
        var oldOnSubmit = el.onsubmit;
        if( el.onsubmit ) {
            el.old_onsubmit = el.onsubmit;
        }

        // helper function to execute the old onSubmit handler
        // and return true if it doesn't exist or returns true
        el.on_submit_good = function() {
            var good = true;
            if( this.old_onsubmit ) good = this.old_onsubmit();
            return good;
        }.bindAsEventListener(el);

        // setup the onSubmit handler to handle form submissions caused
        // by clicking on a 'submit' button.
        el.observe('submit', function(event) {
            if( this.on_submit_good ) Krang.ajax_form_submit(this);
            Event.stop(event);
        }.bindAsEventListener(el));

        // save a non-ajax version of the submit in case we need it
        // (like sending the request to a new window via Krang.submit_form_new_window )
        el.old_submit = el.submit;
        el.non_ajax_submit = function() {
            if( this.on_submit_good ) this.old_submit();
        }.bindAsEventListener(el);

        // Krang likes to call submit() directly on forms
        // which unfortunately in JS is handled differently 
        // than a user clicking on a 'submit' button.
        // (meaning it doesn't invoke the onSubmit handler that we took care of in the section above) 
        el.submit = function() {
            if( this.on_submit_good ) Krang.ajax_form_submit(this);
        }.bindAsEventListener(el);
    },
    // create an autocomplete widget. This involves creating a div
    // in which to place the results and creating an Ajax.Autocompleter
    // object. We only do this if the use has the "use_autocomplete"
    // preference
    'input.autocomplete' : function(el) {
        var pref = Krang.my_prefs();
        if( pref.use_autocomplete ) {
            // add a new div of class 'autocomplete' right below this input
            var div = Builder.node('div', { className: 'autocomplete', style : 'display:none' }); 
            el.parentNode.insertBefore(div, el.nextSibling);
            
            // turn off browser's built-in auto-complete
            el.autocomplete = "off";

            // the request_url is first retrieved from the action of the form
            // and second from the url of the current document.
            var request_url = el.form.readAttribute('action')
                || document.URL;

            new Ajax.Autocompleter(
                el,
                div,
                request_url,
                { 
                    paramName: 'phrase',
                    tokens   : [' '],
                    callback : function(el, url) {
                        url = url + '&rm=autocomplete';
                        return url;
                    }
                }
            );
        }
    }
};
Behaviour.register(rules);
