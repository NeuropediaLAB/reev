import { API_V1_BASE_PREFIX } from '@/api/common'

import type {
  AcmgAssessment,
  CaseArchiveSummary,
  CaseVariant,
  CaseVariantCreate,
  CaseVariantUpdate,
  DataVersion,
  FailureInfo,
  ReanalysisAlert,
  ReanalysisRun
} from './types'

/**
 * Access to the casearchive part of the API.
 */
export class CaseArchiveClient {
  private apiBaseUrl: string

  constructor(apiBaseUrl?: string) {
    this.apiBaseUrl = apiBaseUrl ?? API_V1_BASE_PREFIX
  }

  private async requestJson<T>(
    url: string,
    method: string,
    body?: any
  ): Promise<{ ok: boolean; data: T | FailureInfo }> {
    const response = await fetch(url, {
      method,
      mode: 'cors',
      credentials: 'include',
      headers:
        body !== undefined
          ? { accept: 'application/json', 'Content-Type': 'application/json' }
          : { accept: 'application/json' },
      body: body !== undefined ? JSON.stringify(body) : undefined
    })
    if (response.status === 204) {
      return { ok: true, data: undefined as T }
    }
    const data = await response.json()
    return { ok: response.ok, data }
  }

  /**
   * Lists all followed variants of a case.
   */
  async fetchVariants(caseId: string): Promise<{ ok: boolean; data: CaseVariant[] | FailureInfo }> {
    return this.requestJson(`${this.apiBaseUrl}casearchive/${caseId}/variants`, 'GET')
  }

  /**
   * Follows a variant within a case.
   */
  async createVariant(
    caseId: string,
    payload: CaseVariantCreate
  ): Promise<{ ok: boolean; data: CaseVariant | FailureInfo }> {
    return this.requestJson(`${this.apiBaseUrl}casearchive/${caseId}/variants`, 'POST', payload)
  }

  /**
   * Imports the current user's bookmarks into the case.
   */
  async importBookmarks(
    caseId: string,
    objTypes: string[] = ['seqvar'],
    overwrite: boolean = false
  ): Promise<{ ok: boolean; data: CaseVariant[] | FailureInfo }> {
    return this.requestJson(
      `${this.apiBaseUrl}casearchive/${caseId}/variants/import-bookmarks`,
      'POST',
      {
        obj_types: objTypes,
        overwrite
      }
    )
  }

  /**
   * Updates a followed variant.
   */
  async updateVariant(
    caseId: string,
    variantId: string,
    payload: CaseVariantUpdate
  ): Promise<{ ok: boolean; data: CaseVariant | FailureInfo }> {
    return this.requestJson(
      `${this.apiBaseUrl}casearchive/${caseId}/variants/${variantId}`,
      'PATCH',
      payload
    )
  }

  /**
   * Stops following a variant (removes it and its ACMG history).
   */
  async deleteVariant(
    caseId: string,
    variantId: string
  ): Promise<{ ok: boolean; data: void | FailureInfo }> {
    return this.requestJson(
      `${this.apiBaseUrl}casearchive/${caseId}/variants/${variantId}`,
      'DELETE'
    )
  }

  /**
   * Full ACMG classification history of a followed variant.
   */
  async fetchHistory(
    caseId: string,
    variantId: string
  ): Promise<{ ok: boolean; data: AcmgAssessment[] | FailureInfo }> {
    return this.requestJson(
      `${this.apiBaseUrl}casearchive/${caseId}/variants/${variantId}/history`,
      'GET'
    )
  }

  /**
   * Re-runs the ACMG classification of one variant right now.
   */
  async reanalyzeVariant(
    caseId: string,
    variantId: string
  ): Promise<{ ok: boolean; data: AcmgAssessment | null | FailureInfo }> {
    return this.requestJson(
      `${this.apiBaseUrl}casearchive/${caseId}/variants/${variantId}/reanalyze`,
      'POST'
    )
  }

  /**
   * Re-runs the ACMG classification of every followed variant of a case.
   */
  async reanalyzeCase(caseId: string): Promise<{ ok: boolean; data: ReanalysisRun | FailureInfo }> {
    return this.requestJson(`${this.apiBaseUrl}casearchive/${caseId}/reanalyze`, 'POST')
  }

  /**
   * Alerts raised when a classification in this case changed.
   */
  async fetchAlerts(
    caseId: string,
    onlyUnread: boolean = false
  ): Promise<{ ok: boolean; data: ReanalysisAlert[] | FailureInfo }> {
    return this.requestJson(
      `${this.apiBaseUrl}casearchive/${caseId}/alerts?only_unread=${onlyUnread}`,
      'GET'
    )
  }

  /**
   * Marks an alert as read.
   */
  async markAlertRead(
    caseId: string,
    alertId: string
  ): Promise<{ ok: boolean; data: ReanalysisAlert | FailureInfo }> {
    return this.requestJson(
      `${this.apiBaseUrl}casearchive/${caseId}/alerts/${alertId}/read`,
      'POST'
    )
  }

  /**
   * Counters for the case view.
   */
  async fetchSummary(
    caseId: string
  ): Promise<{ ok: boolean; data: CaseArchiveSummary | FailureInfo }> {
    return this.requestJson(`${this.apiBaseUrl}casearchive/${caseId}/summary`, 'GET')
  }

  /**
   * Versions of the reference databases seen by the instance.
   */
  async fetchDataVersions(): Promise<{ ok: boolean; data: DataVersion[] | FailureInfo }> {
    return this.requestJson(`${this.apiBaseUrl}casearchive/data-versions`, 'GET')
  }
}
