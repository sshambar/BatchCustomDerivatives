{footer_script require="jquery"}
function bcd_selectAll() {
  $("#bcd_action_generate_derivatives input[type=checkbox]").prop("checked", true);
}

function bcd_selectNone() {
  $("#bcd_action_generate_derivatives input[type=checkbox]").prop("checked", false);
}

var bcd_derivatives = {
  elements: null,
  done: 0,
  total: 0,

  finished: function() {
    return bcd_derivatives.done == bcd_derivatives.total && bcd_derivatives.elements && bcd_derivatives.elements.length==0;
  }
};

function bcd_progress(success) {
  jQuery('#progressBar').progressBar(bcd_derivatives.done, {
    max: bcd_derivatives.total,
    textFormat: 'fraction',
    boxImage: 'themes/default/images/progressbar.gif',
    barImage: 'themes/default/images/progressbg_orange.gif'
  });
  if (success !== undefined) {
    var type = success ? 'regenerateSuccess': 'regenerateError',
	s = jQuery('[name="'+type+'"]').val();
    jQuery('[name="'+type+'"]').val(++s);
  }

  if (bcd_derivatives.finished()) {
    jQuery('#applyAction').click();
  }
}

function bcd_getDerivativeUrls() {
  var ids = bcd_derivatives.elements.splice(0, 500);
  var params = { max_urls: 100000, ids: ids, types: [] };
  jQuery("#bcd_action_generate_derivatives input").each( function(i, t) {
    if ($(t).is(":checked"))
      params.types.push( t.value );
  } );

  jQuery.ajax( {
    type: "POST",
    url: 'ws.php?format=json&method=bcd.getMissingCustomDerivatives',
    data: params,
    dataType: "json",
    success: function(data) {
      if (!data.stat || data.stat != "ok") {
	return;
      }
      bcd_derivatives.total += data.result.urls.length;
      bcd_progress();
      for (var i=0; i < data.result.urls.length; i++) {
	jQuery.manageAjax.add("queued", {
	  type: 'GET',
	  url: data.result.urls[i] + "&ajaxload=true",
	  dataType: 'json',
	  success: ( function(data) { bcd_derivatives.done++; bcd_progress(true) }),
	  error: ( function(data) { bcd_derivatives.done++; bcd_progress(false) })
	});
      }
      if (bcd_derivatives.elements.length)
	setTimeout( bcd_getDerivativeUrls, 25 * (bcd_derivatives.total-bcd_derivatives.done));
    }
  });
}
$(document).ready(function() {
  jQuery('#applyAction').click(function() {
    var action = jQuery('[name="selectAction"]').val();
    if (action != 'batch_custom_derivatives'
	|| bcd_derivatives.finished() )
    {
      return true;
    }

    jQuery('.bulkAction').hide();

    var queuedManager = jQuery.manageAjax.create('queued', {
      queue: true,
      cacheResponse: false,
      maxRequests: 1
    });

    bcd_derivatives.elements = [];
    if (jQuery('input[name="setSelected"]').is(':checked'))
      bcd_derivatives.elements = all_elements;
    else
      jQuery('.thumbnails input[type=checkbox]').each(function() {
	if (jQuery(this).is(':checked')) {
	  bcd_derivatives.elements.push(jQuery(this).val());
	}
      });

    jQuery('#applyActionBlock').hide();
    jQuery('select[name="selectAction"]').hide();
    jQuery('#regenerationMsg').show();

    bcd_progress();
    bcd_getDerivativeUrls();
    return false;
  });
});
{/footer_script}
<!-- generate derivatives -->
<div id="bcd_action_generate_derivatives" class="bulkAction">
  <a href="javascript:bcd_selectAll()">{'All'|translate}</a>,
  <a href="javascript:bcd_selectNone()">{'None'|translate}</a>
  <br>
  {foreach from=$bcd_derivatives_types key=type item=disp}
    <label><input type="checkbox" name="bcd_derivatives_type[]" value="{$type}"> {$disp}</label>
  {/foreach}
</div>
