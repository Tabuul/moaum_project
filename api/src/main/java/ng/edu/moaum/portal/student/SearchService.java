package ng.edu.moaum.portal.student;

import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Search finds one record; the scope bar narrows a list.
 *
 * <p>Every call with a term writes a row to {@code people.search_log} — the
 * term, the kind and how many it found. That write is the reason this is a
 * transactional method on a read: looking a person up is processing their
 * personal data whether or not anything changes, and the Registrar reviews
 * the log quarterly.
 */
@Service
class SearchService {

    static final Set<String> KINDS = Set.of("all", "students", "staff", "courses", "credentials");

    private final SearchRepository search;

    SearchService(SearchRepository search) {
        this.search = search;
    }

    @Transactional
    SearchHit.Result find(String q, String kind) {
        String term = q == null ? "" : q.trim();
        String want = kind == null || kind.isBlank() || !KINDS.contains(kind) ? "all" : kind;
        if (term.isEmpty()) {
            return new SearchHit.Result("", want, List.of(), null, 0);
        }
        String like = "%" + term.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        List<SearchHit> hits = new ArrayList<>();
        if (want.equals("all") || want.equals("students")) {
            hits.addAll(search.students(like));
        }
        if (want.equals("all") || want.equals("staff")) {
            hits.addAll(search.staff(like));
        }
        if (want.equals("all") || want.equals("courses")) {
            hits.addAll(search.courses(like));
        }
        if (want.equals("all") || want.equals("credentials")) {
            hits.addAll(search.credentials(like));
        }
        search.log(term, want, hits.size());
        return new SearchHit.Result(term, want, hits, exact(term, hits), hits.size());
    }

    /** An identifier typed in full goes straight to the record. */
    private SearchHit exact(String term, List<SearchHit> hits) {
        return hits.stream()
                .filter(h -> h.identifier() != null && h.identifier().equalsIgnoreCase(term))
                .findFirst()
                .orElse(null);
    }
}
