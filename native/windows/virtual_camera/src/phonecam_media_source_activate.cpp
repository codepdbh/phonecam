#include "phonecam_media_source_activate.h"

PhoneCamMediaSourceActivate::PhoneCamMediaSourceActivate() {
    PhoneCamComObjectCreated(); MFCreateAttributes(&m_attributes, 8);
}
PhoneCamMediaSourceActivate::~PhoneCamMediaSourceActivate() {
    m_source.Reset(); PhoneCamComObjectDestroyed();
}
STDMETHODIMP PhoneCamMediaSourceActivate::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER; *ppv = nullptr;
    if (riid == IID_IUnknown || riid == IID_IMFAttributes || riid == IID_IMFActivate) {
        *ppv = static_cast<IMFActivate*>(this); AddRef(); return S_OK;
    }
    return E_NOINTERFACE;
}
STDMETHODIMP_(ULONG) PhoneCamMediaSourceActivate::AddRef() { return ++m_refs; }
STDMETHODIMP_(ULONG) PhoneCamMediaSourceActivate::Release() {
    ULONG count = --m_refs; if (!count) delete this; return count;
}
STDMETHODIMP PhoneCamMediaSourceActivate::ActivateObject(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER; *ppv = nullptr;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_source) {
        m_source = new PhoneCamMediaSource();
        ComPtr<IMFAttributes> sourceAttributes;
        if (SUCCEEDED(m_source->GetSourceAttributes(&sourceAttributes)) && m_attributes)
            m_attributes->CopyAllItems(sourceAttributes.Get());
    }
    return m_source->QueryInterface(riid, ppv);
}
STDMETHODIMP PhoneCamMediaSourceActivate::ShutdownObject() {
    // Frame Server can release/shutdown the activation helper immediately
    // after ActivateObject while retaining its own IMFMediaSource reference.
    // The official virtual-camera activation contract therefore treats this
    // as a no-op; shutting the source here invalidates that retained object.
    return S_OK;
}
STDMETHODIMP PhoneCamMediaSourceActivate::DetachObject() {
    std::lock_guard<std::mutex> lock(m_mutex); m_source.Reset(); return S_OK;
}

#define FORWARD(method, ...) return m_attributes ? m_attributes->method(__VA_ARGS__) : E_FAIL
STDMETHODIMP PhoneCamMediaSourceActivate::GetItem(REFGUID k, PROPVARIANT* v) { FORWARD(GetItem, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetItemType(REFGUID k, MF_ATTRIBUTE_TYPE* t) { FORWARD(GetItemType, k, t); }
STDMETHODIMP PhoneCamMediaSourceActivate::CompareItem(REFGUID k, REFPROPVARIANT v, BOOL* r) { FORWARD(CompareItem, k, v, r); }
STDMETHODIMP PhoneCamMediaSourceActivate::Compare(IMFAttributes* a, MF_ATTRIBUTES_MATCH_TYPE t, BOOL* r) { FORWARD(Compare, a, t, r); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetUINT32(REFGUID k, UINT32* v) { FORWARD(GetUINT32, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetUINT64(REFGUID k, UINT64* v) { FORWARD(GetUINT64, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetDouble(REFGUID k, double* v) { FORWARD(GetDouble, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetGUID(REFGUID k, GUID* v) { FORWARD(GetGUID, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetStringLength(REFGUID k, UINT32* v) { FORWARD(GetStringLength, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetString(REFGUID k, LPWSTR v, UINT32 s, UINT32* l) { FORWARD(GetString, k, v, s, l); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetAllocatedString(REFGUID k, LPWSTR* v, UINT32* l) { FORWARD(GetAllocatedString, k, v, l); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetBlobSize(REFGUID k, UINT32* s) { FORWARD(GetBlobSize, k, s); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetBlob(REFGUID k, UINT8* b, UINT32 s, UINT32* z) { FORWARD(GetBlob, k, b, s, z); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetAllocatedBlob(REFGUID k, UINT8** b, UINT32* s) { FORWARD(GetAllocatedBlob, k, b, s); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetUnknown(REFGUID k, REFIID i, LPVOID* v) { FORWARD(GetUnknown, k, i, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::SetItem(REFGUID k, REFPROPVARIANT v) { FORWARD(SetItem, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::DeleteItem(REFGUID k) { FORWARD(DeleteItem, k); }
STDMETHODIMP PhoneCamMediaSourceActivate::DeleteAllItems() { FORWARD(DeleteAllItems); }
STDMETHODIMP PhoneCamMediaSourceActivate::SetUINT32(REFGUID k, UINT32 v) { FORWARD(SetUINT32, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::SetUINT64(REFGUID k, UINT64 v) { FORWARD(SetUINT64, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::SetDouble(REFGUID k, double v) { FORWARD(SetDouble, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::SetGUID(REFGUID k, REFGUID v) { FORWARD(SetGUID, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::SetString(REFGUID k, LPCWSTR v) { FORWARD(SetString, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::SetBlob(REFGUID k, const UINT8* b, UINT32 s) { FORWARD(SetBlob, k, b, s); }
STDMETHODIMP PhoneCamMediaSourceActivate::SetUnknown(REFGUID k, IUnknown* v) { FORWARD(SetUnknown, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::LockStore() { FORWARD(LockStore); }
STDMETHODIMP PhoneCamMediaSourceActivate::UnlockStore() { FORWARD(UnlockStore); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetCount(UINT32* c) { FORWARD(GetCount, c); }
STDMETHODIMP PhoneCamMediaSourceActivate::GetItemByIndex(UINT32 i, GUID* k, PROPVARIANT* v) { FORWARD(GetItemByIndex, i, k, v); }
STDMETHODIMP PhoneCamMediaSourceActivate::CopyAllItems(IMFAttributes* d) { FORWARD(CopyAllItems, d); }
#undef FORWARD
