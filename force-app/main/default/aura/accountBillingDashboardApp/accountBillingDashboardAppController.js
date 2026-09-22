({
    init: function(component, event, helper) {
        var pageRef = component.get("v.pageReference");
        if (pageRef && pageRef.state && pageRef.state.c__accountId) {
            component.set("v.accountId", pageRef.state.c__accountId);
        }
    }
})
