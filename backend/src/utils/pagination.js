import { z } from 'zod';

export const pageParams = z
  .object({
    page: z.coerce.number().int().min(1).default(1),
    limit: z.coerce.number().int().min(1).max(200).default(50),
    from: z.coerce.date().optional(),
    to: z.coerce.date().optional(),
  })
  .passthrough()
  .transform((v) => ({ ...v, skip: (v.page - 1) * v.limit }));

export function paged(items, { page, limit, total }) {
  return { items, page, limit, total, hasMore: page * limit < total };
}

/** Builds a Mongo date-range filter from validated from/to query params. */
export function dateRange(field, { from, to }) {
  if (!from && !to) return {};
  const range = {};
  if (from) range.$gte = from;
  if (to) range.$lte = to;
  return { [field]: range };
}
