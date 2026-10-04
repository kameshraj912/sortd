// soon.sortd.page was the beta launch page. It was merged into sortd.page on 4 Oct 2026.
// Every address here now goes to the home page for good (301), so old links
// (the Instagram bio, shared posts) keep working.
export default {
  fetch() {
    return Response.redirect("https://sortd.page/", 301);
  },
};
