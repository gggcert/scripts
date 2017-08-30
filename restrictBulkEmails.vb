'=================================================================
'Description:
'           Outlook macro to restrict sending mails if TO+CC recipients are more then 10.
'           A work around bypass to this restriction can be done by adding "OK@OK.OK" address to bcc
'           handle distribution lists (in TO or CC ) by quering the address book directory for members count (one level deep !!)
' author : Gilad Finkelstein
' version: 1.0 13/8/2017
' supported verions: outlook > 2010
' installation: Put the content of the code in your ThisOutlookSession project in VBA (Alt+F11) or directly in the VbaProject.OTM file
'               Macro on the outlook should be enabled in File->OPtions->Trust center ->setting -> macro definition tab . enable macro and check the box to enale on current enabled code
'=================================================================
Private Sub Application_ItemSend(ByVal Item As Object, Cancel As Boolean)
    Dim ReciptCount As Long
    Dim OKFlag As Integer
    Dim debugFlag As Boolean
 
    ' static parms you may want to change for specific use cases
    Const maxNoneBcc = 10 ' allow no more then 10 users in none bcc mode
    Const rootAddressListsName = "Contacts"  '"All Distribution Lists" and it can support hebrew names too
    Const ignoreString = "OK@OK.OK"
 
    Dim olApp As Outlook.Application
    Dim olNS As Outlook.NameSpace
    Dim olAL As Outlook.AddressList
    Dim olEntry As Outlook.AddressEntry
    'Dim olMember As Outlook.AddressEntry
    Dim lMemberCount As Long
    'Dim objMail As Outlook.MailItem
 
    debugFlag = True 'when in debug mode it will not send your file so you must chage this to false for production
 
On Error Resume Next
    OKFlag = 0
    ReciptCount = 1
    If debugFlag Then
        Cancel = True 'debug mode never send an email
    Else
        Cancel = False 'default send email, you may consider changing it to default not send the email
    End If
    'if a sepecial string appears in bcc ignore the all logic
    OKFlag = InStr(Item.BCC, ignoreString)
    If (OKFlag = 0) Then
        'lets see how many recipients do we have only if its more then the max trigger error message and quit
        ReciptCount = Item.Recipients.Count
        Set olApp = Outlook.Application
        Set olNS = olApp.GetNamespace("MAPI")
        ' here we manually set the address book for looking up distribution lists. there should only be one such root directory
        Set olAL = olNS.AddressLists(rootAddressListsName) ' ("?????? ?????") '"All Distribution Lists"
 
        'filter out bcc entries
        For Each Recipient In Item.Recipients
            If Recipient.Type = olBCC Then
                ReciptCount = ReciptCount - 1 ' we do not count bcc recipients
            Else
                If Recipient.DisplayType <> olUser Then 'only if this is not a norml user,check as a dist list
                    'lets see if someone is using a dist group in which case we need to count its members
                    recpientName = Recipient.Name ' "CERTeam"
                    'iterate over all dist lists for each given recipient address if it is a list find out how many members are in
                     For Each olEntry In olAL.AddressEntries
                        If olEntry.Name = recpientName Then
                            ' get count of dist list members
                            lMemberCount = olEntry.Members.Count
                            ReciptCount = ReciptCount - 1 + lMemberCount 'replace group count (1) with either 0 (no memvbers) or group members count
                            Exit For
                        End If
                     Next
                End If
            End If
        Next
        If (ReciptCount > maxNoneBcc) Then
             Cancel = MsgBox("Too many Recipients in ""TO"" or ""CC"" please send in BCC only" & vbNewLine & "***To bypass this you can add " & ignoreString & " address to BCC recipients***", vbCritical)
             Cancel = True
             Exit Sub
         End If
 
       'Dim snd As Outlook.SelectNamesDialog ' =  Application.Session.GetSelectNamesDialog()
       ' Dim addrLists As Outlook.AddressLists '=   Application.Session.AddressLists
        'Dim addrEntry As Outlook.AddressEntry
    '    Dim exchDL As Outlook.ExchangeDistributionList
       ' Dim addrEntries As Outlook.AddressEntries
      ' Cancel = True
 
    '    Set snd = Application.Session.GetSelectNamesDialog()
    '    Set addrLists = Application.Session.AddressLists
    '    For Each addrList In addrLists
    '        If addrList.Name = "All Distribution Lists" Or addrList.Name = "?????? ?????" Then
    '            'snd.InitialAddressList = addrList
    ''            For Each addrEntry In addrList
    '                   lbl = addrEntry
    '            Next
    '            Exit For
    '        End If
    '    Next
 
 
 
 
   End If ' okflag
End Sub
 
 
