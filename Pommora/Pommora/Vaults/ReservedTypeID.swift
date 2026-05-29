import Foundation

/// Reserved type identifiers for singleton operational schemas (Agenda Tasks
/// and Agenda Events) used as relation targets in reverse-property storage.
enum ReservedTypeID {
    static let agendaTasks  = "_agenda_tasks"
    static let agendaEvents = "_agenda_events"
}
