# RevisionSearchResultTrait::initFromTitle hits PreconditionException for invalid Title rows from Special:Search

**MediaWiki version:** 1.44 (REL1_44)

## Summary

`Special:Search` triggers a `Wikimedia\Assert\PreconditionException` when the SearchMySQL result set contains rows whose `(page_namespace, page_title)` cannot be reconstructed into a proper Title — for example, a page whose `page_title` begins with the textual prefix of a custom namespace defined later (so `page_namespace = 0` but `Title::makeTitle(0, 'Record:_Foo')->canExist()` is false).

## Stack trace

```
PreconditionException: This Title instance does not represent a proper page, but merely a link target.
#0 Wikimedia\Assert\Assert::precondition           includes/title/Title.php:3830
#1 Title->assertProperPage                         includes/title/Title.php:3813
#2 Title->getId                                    includes/Revision/RevisionStore.php:1841
#3 RevisionStore->ensureRevisionRowMatchesPage     includes/Revision/RevisionStore.php:1746
#4 RevisionStore->newRevisionFromRowAndSlots       includes/Revision/RevisionStore.php:1622
#5 RevisionStore->newRevisionFromRow               includes/Revision/RevisionStore.php:2360
#6 RevisionStore->loadRevisionFromConds            includes/Revision/RevisionStore.php:1306
#7 RevisionStore->getRevisionByTitle               includes/search/RevisionSearchResultTrait.php:52
#8 RevisionSearchResult->initFromTitle             includes/search/RevisionSearchResult.php:18
... up through SearchEngine->maybePaginate / SpecialSearch->showResults
```

## Reproduction

1. Define a custom namespace, e.g. `$wgExtraNamespaces[102] = 'Record'`.
2. Create a page with `page_namespace = 0` and `page_title = 'Record:_Foo'` (e.g. via raw SQL or by importing a dump from before the namespace was defined).
3. Run a search whose result set is large enough to include that row (e.g. `?limit=500&profile=all&search=<term-matching-the-row>`).
4. Special:Search returns HTTP 500.

## Expected behavior

A row whose Title can't be reconstructed should be treated like any other broken / missing-revision row (`isBrokenTitle()`, `isMissingRevision()`), not throw a fatal precondition exception that takes the whole page down.

## Suggested fix

Guard the body of `RevisionSearchResultTrait::initFromTitle` with `$title->canExist()` so that downstream `getRevisionByTitle` is only attempted on Titles that can plausibly map to a page row. The existing `isMissingRevision()` flow then handles the case correctly.

```diff
 protected function initFromTitle( $title ) {
     $this->mTitle = $title;
-    if ( $title !== null ) {
+    if ( $title !== null && $title->canExist() ) {
```

## Notes

We carry this as a local patch (`patches/search-skip-invalid-title.patch`) on the [Attu Project Wiki](https://attuproject.org); happy to upstream the diff if there's a preferred channel.
