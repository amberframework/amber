var reload = document.querySelector('[role~="reload-toggle"]');
var reloadTimeout;
recursiveReload();
on(reload, 'click', reloadOnclick);
function recursiveReload() {
    var request = new XMLHttpRequest();
    request.open('GET', window.location.href, true);
    request.onreadystatechange = function () {
        if (request.readyState === 4) {
            var errorId = request.getResponseHeader('Client-Reload');
            if (errorId === '<%= @error_id %>') {
                reloadTimeout = setTimeout(function () {
                    recursiveReload();
                }, 1000)
            } else if (errorId === 'true') {
                window.location.reload();
            }
        }
    };
    request.send();
}
