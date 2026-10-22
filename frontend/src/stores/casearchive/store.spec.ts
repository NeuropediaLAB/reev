import { StoreState } from '@bihealth/reev-frontend-lib/stores'
import { createTestingPinia } from '@pinia/testing'
import { setActivePinia } from 'pinia'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import createFetchMock from 'vitest-fetch-mock'

import { useCaseArchiveStore } from './store'

const fetchMocker = createFetchMock(vi)

/** Example followed variant as returned by the API. */
const MOCK_VARIANT = {
  id: 'variant-uuid',
  case_info: 'case-uuid',
  bookmark: null,
  obj_type: 'seqvar',
  obj_id: 'grch38-17-41195937-C-T',
  genome_build: 'grch38',
  gene_symbol: 'TTN',
  hgnc_id: 'HGNC:12463',
  transcript: null,
  label: 'TTN variant',
  notes: null,
  follow: true,
  added_at: '2026-10-01T10:00:00',
  last_analyzed_at: null,
  latest: {
    id: 'assessment-uuid',
    acmg_class: 'Likely pathogenic',
    criteria: null,
    source: 'acmg',
    engine_version: '1.0',
    data_signature: null,
    data_versions: null,
    is_conflicting: false,
    created_at: '2026-10-01T10:00:00'
  }
}

describe('case archive store', () => {
  beforeEach(() => {
    fetchMocker.resetMocks()
    setActivePinia(
      createTestingPinia({
        stubActions: false,
        initialState: {
          user: {
            storeState: StoreState.Active,
            currentUser: {
              id: 'test',
              email: 'test@example.com',
              is_active: true,
              is_superuser: false,
              is_verified: true,
              oauth_accounts: []
            }
          },
          caseInfo: {
            storeState: StoreState.Active,
            caseInfo: { id: 'case-uuid', pseudonym: 'case', diseases: [], hpoTerms: [] }
          }
        }
      })
    )
    fetchMocker.enableMocks()
    fetchMocker.resetMocks()
  })

  it('loads variants, summary and alerts on initialize', async () => {
    fetchMocker
      .mockResponseOnce(JSON.stringify([MOCK_VARIANT]), { status: 200 })
      .mockResponseOnce(
        JSON.stringify({ n_variants: 1, n_followed: 1, n_alerts_unread: 0, by_class: {} }),
        { status: 200 }
      )
      .mockResponseOnce(JSON.stringify([]), { status: 200 })

    const store = useCaseArchiveStore()
    await store.initialize()

    expect(store.storeState).toBe(StoreState.Active)
    expect(store.variants).toHaveLength(1)
    expect(store.variants[0].obj_id).toBe('grch38-17-41195937-C-T')
    expect(store.summary?.n_variants).toBe(1)
    expect(store.alerts).toHaveLength(0)
  })

  it('stays inactive when not logged in', async () => {
    setActivePinia(
      createTestingPinia({
        stubActions: false,
        initialState: {
          user: { storeState: StoreState.Initial, currentUser: null },
          caseInfo: { storeState: StoreState.Initial, caseInfo: null }
        }
      })
    )
    fetchMocker
      .mockResponseOnce(JSON.stringify([]), { status: 200 })
      .mockResponseOnce(JSON.stringify({ detail: 'unauthenticated' }), { status: 401 })
    const store = useCaseArchiveStore()
    await store.initialize()
    expect(store.storeState).not.toBe(StoreState.Active)
  })

  it('marks an alert as read and refreshes', async () => {
    fetchMocker
      .mockResponseOnce(JSON.stringify([]), { status: 200 })
      .mockResponseOnce(
        JSON.stringify({ n_variants: 0, n_followed: 0, n_alerts_unread: 0, by_class: {} }),
        { status: 200 }
      )
      .mockResponseOnce(
        JSON.stringify([
          {
            id: 'alert-uuid',
            case_info: 'case-uuid',
            case_variant: 'variant-uuid',
            old_class: 'VUS',
            new_class: 'Likely pathogenic',
            message: null,
            severity: 'high',
            read_at: null,
            created_at: '2026-10-02T10:00:00'
          }
        ]),
        { status: 200 }
      )
      .mockResponseOnce(
        JSON.stringify({
          id: 'alert-uuid',
          case_info: 'case-uuid',
          case_variant: 'variant-uuid',
          old_class: 'VUS',
          new_class: 'Likely pathogenic',
          message: null,
          severity: 'high',
          read_at: '2026-10-03T10:00:00',
          created_at: '2026-10-02T10:00:00'
        }),
        { status: 200 }
      )
      .mockResponseOnce(JSON.stringify([]), { status: 200 })
      .mockResponseOnce(
        JSON.stringify({ n_variants: 0, n_followed: 0, n_alerts_unread: 0, by_class: {} }),
        { status: 200 }
      )

    const store = useCaseArchiveStore()
    await store.initialize()
    await store.markAlertRead('alert-uuid')

    expect(store.alerts).toHaveLength(0)
    expect(store.nAlertsUnread).toBe(0)
  })
})
