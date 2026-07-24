/**
 * Zod-backed request validation. Replaces the parsed value back onto the
 * request so handlers receive coerced, trimmed, defaulted data rather than raw
 * user input.
 */
export const validate =
  ({ body, query, params }) =>
  (req, res, next) => {
    try {
      if (body) req.body = body.parse(req.body);
      if (params) req.params = params.parse(req.params);
      if (query) {
        // req.query is a getter-only property in Express 5; assign to a
        // separate field that handlers read instead.
        req.validatedQuery = query.parse(req.query);
      }
      next();
    } catch (err) {
      next(err);
    }
  };

/** Convenience accessor so handlers do not care which Express version is in use. */
export const q = (req) => req.validatedQuery ?? req.query;
