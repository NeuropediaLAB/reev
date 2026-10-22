/** Types for the case archive API (mirrors backend app/schemas/casearchive.py). */

/** Bookmark/variant object type as returned by the API. */
export type CaseVariantObjType = 'seqvar' | 'strucvar'

/** One stored ACMG classification of a followed variant. */
export interface AcmgAssessment {
  id: string
  acmg_class: string
  criteria: Record<string, any> | null
  source: string
  engine_version: string
  data_signature: string | null
  data_versions: Record<string, any> | null
  is_conflicting: boolean
  created_at: string
}

/** A followed variant with its latest classification. */
export interface CaseVariant {
  id: string
  case_info: string
  bookmark: string | null
  obj_type: string
  obj_id: string
  genome_build: string
  gene_symbol: string | null
  hgnc_id: string | null
  transcript: string | null
  label: string | null
  notes: string | null
  follow: boolean
  added_at: string
  last_analyzed_at: string | null
  latest: AcmgAssessment | null
}

/** Payload to follow a variant within a case. */
export interface CaseVariantCreate {
  obj_type?: CaseVariantObjType
  obj_id: string
  genome_build?: 'grch37' | 'grch38' | null
  gene_symbol?: string | null
  hgnc_id?: string | null
  transcript?: string | null
  label?: string | null
  notes?: string | null
  follow?: boolean
}

/** Editable fields of a followed variant. */
export interface CaseVariantUpdate {
  follow?: boolean
  gene_symbol?: string | null
  transcript?: string | null
  label?: string | null
  notes?: string | null
}

/** A batch re-analysis run. */
export interface ReanalysisRun {
  id: string
  trigger: string
  status: string
  data_signature: string | null
  data_versions: Record<string, any> | null
  n_variants: number
  n_changed: number
  n_failed: number
  error: string | null
  started_at: string
  finished_at: string | null
}

/** An alert about a changed classification. */
export interface ReanalysisAlert {
  id: string
  case_info: string
  case_variant: string
  old_class: string | null
  new_class: string
  message: string | null
  severity: string
  read_at: string | null
  created_at: string
}

/** A known version of a reference database. */
export interface DataVersion {
  id: string
  source: string
  version: string
  first_seen_at: string
}

/** Counters shown in the case view. */
export interface CaseArchiveSummary {
  n_variants: number
  n_followed: number
  n_alerts_unread: number
  last_run: ReanalysisRun | null
  by_class: Record<string, number>
}

/** Response envelope for failures. */
export interface FailureInfo {
  detail: string
}

/** Type guard for AcmgAssessment. */
export const isAcmgAssessment = (value: any): value is AcmgAssessment =>
  value !== null && typeof value === 'object' && 'acmg_class' in value && 'created_at' in value

/** Type guard for CaseVariant. */
export const isCaseVariant = (value: any): value is CaseVariant =>
  value !== null && typeof value === 'object' && 'obj_id' in value && 'case_info' in value

/** Type guard for ReanalysisRun. */
export const isReanalysisRun = (value: any): value is ReanalysisRun =>
  value !== null && typeof value === 'object' && 'n_variants' in value && 'trigger' in value

/** Type guard for ReanalysisAlert. */
export const isReanalysisAlert = (value: any): value is ReanalysisAlert =>
  value !== null && typeof value === 'object' && 'new_class' in value && 'severity' in value

/** Type guard for DataVersion. */
export const isDataVersion = (value: any): value is DataVersion =>
  value !== null && typeof value === 'object' && 'source' in value && 'version' in value

/** Type guard for CaseArchiveSummary. */
export const isCaseArchiveSummary = (value: any): value is CaseArchiveSummary =>
  value !== null && typeof value === 'object' && 'n_alerts_unread' in value && 'by_class' in value

/** Type guard for failure responses. */
export const isFailureInfo = (value: any): value is FailureInfo =>
  value !== null && typeof value === 'object' && 'detail' in value
