unit PasDoc_TagManager;

interface

uses
  SysUtils,
  Classes,
  PasDoc_Types;

type
  TTagManager = class;

  { TagManager can be useful for various things:

    E.g. you can use it in tag handler to report a message
    by @code(TagManager.DoMessage(...)), this is e.g. used
    by implementation of TPasItem.StoreAbstractTag.
    
    You could also use this to manually force recursive
    behavior of a given tag. I.e let's suppose that you
    have a tag with TagOptions = [toParameterRequired],
    so the TagDesc parameter passed to handler was
    not recursively expanded. Then you can do inside your handler
    @longcode# NewTagDesc := TagManager.Execute(TagDesc) #
    and this way you have explicitly recursively expanded the tag.

    This is not used anywhere for now, but this will be used
    when I will implement auto-linking (making links without
    the need to use @@link tag). Then I will have to make @@nolink
    tag, and TTagManager.Execute will get a parameter
    @code(AutoLink: boolean). Then inside @@nolink tag I will
    be able to call TTagManager.Execute(TagDesc, false)
    thus preventing auto-linking inside text within @@nolink. }
  TTagHandler = procedure(TagManager: TTagManager;
    const TagName: string; const TagDesc: string; var ReplaceStr: string)
    of object;
  TStringConverter = function(const s: string): string of object;

  TTagOption = (
    { This means that tag expects parameters. If this is not included 
      in TagOptions then tag should not be given any parameters,
      i.e. TagDesc passed to @link(TTagHandlerObj.Execute) should be ''.
      We will display a warning if user will try to give
      some parameters for such tag. }
    toParameterRequired, 
    
    { This means that parameters of this tag will be expanded
      before passing them to @link(TTagHandlerObj.Execute).
      This means that we will expand recursive tags inside
      parameters, that we will ConvertString inside parameters,
      that we will handle paragraphs inside parameters etc. --
      all that does @link(TTagManager.Execute).

      If toParameterRequired is not present in TTagOptions than
      it's not important whether you included toRecursiveTags.

      It's useful for some tags to include toParameterRequired
      without including toRecursiveTags, e.g. @@longcode or @@html,
      that want to get their parameters "verbatim", not processed. }
    toRecursiveTags);
      
  TTagOptions = set of TTagOption;

  TTagHandlerObj = class
  private
    FTagHandler: TTagHandler;
    FTagOptions: TTagOptions;
  public
    constructor Create(ATagHandler: TTagHandler;
      const ATagOptions: TTagOptions);

    property TagOptions: TTagOptions read FTagOptions write FTagOptions;

    procedure Execute(TagManager: TTagManager;
      const TagName: string; const TagDesc: string; var ReplaceStr: string);
  end;

  TTagManager = class
  private
    FTags: TStringList;
    FStringConverter: TStringConverter;
    FAbbreviations: TStringList;
    FOnMessage: TPasDocMessageEvent;
    FInsertParagraphs: TStringConverter;

    function ConvertString(const s: string): string;
    procedure Unabbreviate(var s: string);

    { Call InsertParagraphs if assigned, else just returns S. }
    function DoInsertParagraphs(const S: string): string;
  public
    constructor Create;
    destructor Destroy; override;

    { Call OnMessage (if assigned) with given params. }
    procedure DoMessage(const AVerbosity: Cardinal;
      const MessageType: TMessageType; const AMessage: string;
      const AArguments: array of const);

    { This will be used to print messages from within @link(Execute).

      Note that in this unit we essentialy "don't know"
      that parsed Description string is probably attached to some TPasItem.
      It's good that we don't know it (because it makes this class more flexible).
      But it also means that OnMessage that you assign here may want to add
      to passed AMessage something like + ' (Expanded_TPasItem_Name)',
      see e.g. TDocGenerator.DoMessageFromExpandDescription.
      Maybe in the future we will do some descendant of this class,
      like TTagManagerForPasItem. }
    property OnMessage: TPasDocMessageEvent read FOnMessage write FOnMessage;

    { This will be called to insert paragraphs into a text.
      Note that input given to this function will always be
      already processed by @link(StringConverter).

      Design note: I don't think that it would be good to simply
      require user of this class to insert paragraphs inside
      @link(StringConverter). Why ? Because any user of this class
      will want anyway to have something like @link(StringConverter)
      that doesn't insert paragraphs available, because it is needed
      when handling @longcode tag (that should escape characters,
      e.g. '<' ->  '&lt;' in html output, but should not insert paragraphs). }
    property InsertParagraphs: TStringConverter
      read FInsertParagraphs write FInsertParagraphs;

    { See @link(TTagHandlerObj) for the meaning of parameter TagOption.
      Don't worry about the case of TagName, it does *not* matter. }
    procedure AddHandler(const TagName: string; Handler: TTagHandler;
      const TagOptions: TTagOptions);

    function Execute(const Description: string): string;
    property StringConverter: TStringConverter read FStringConverter write FStringConverter;
    property Abbreviations: TStringList read FAbbreviations write FAbbreviations;
  end;

implementation

uses {$ifdef VER1_0} Utils {$else} StrUtils {$endif};

{ TTagHandlerObj }

constructor TTagHandlerObj.Create(ATagHandler: TTagHandler;
  const ATagOptions: TTagOptions);
begin
  inherited Create;
  FTagHandler := ATagHandler;
  FTagOptions := ATagOptions;
end;

procedure TTagHandlerObj.Execute(TagManager: TTagManager;
  const TagName, TagDesc: string; var ReplaceStr: string);
begin
  if Assigned(fTagHandler) then
    fTagHandler(TagManager, TagName, TagDesc, ReplaceStr);
end;

{ TTagManager }

constructor TTagManager.Create;
begin
  inherited Create;
  FTags := TStringList.Create;
  FTags.Sorted := true;
end;

destructor TTagManager.Destroy;
var
  i: integer;
begin
  if FTags <> nil then
    begin
      for i:=0 to FTags.Count-1 do
        FTags.Objects[i].Free;
      FTags.Free;
    end;
  inherited;
end;

procedure TTagManager.AddHandler(const TagName: string; Handler: TTagHandler;
  const TagOptions: TTagOptions);
begin
  FTags.AddObject(LowerCase(Tagname),
    TTagHandlerObj.Create(Handler, TagOptions));
end;

function TTagManager.ConvertString(const s: string): string;
begin
  if Assigned(FStringConverter) then
    Result := FStringConverter(s)
  else
    Result := s;
end;

procedure TTagManager.Unabbreviate(var s: string);
var
  idx: Integer;
begin
  if Assigned(Abbreviations) then begin
    idx := Abbreviations.IndexOfName(s);
    if idx>=0 then begin
      s := Abbreviations.Values[s];
    end;
  end;
end;

procedure TTagManager.DoMessage(const AVerbosity: Cardinal; const
  MessageType: TMessageType; const AMessage: string;
  const AArguments: array of const);
begin
  if Assigned(FOnMessage) then
    FOnMessage(MessageType, Format(AMessage, AArguments), AVerbosity);
end;

function TTagManager.DoInsertParagraphs(const S: string): string;
begin
  if Assigned(InsertParagraphs) then
    Result := InsertParagraphs(S) else
    Result := S;
end;

function TTagManager.Execute(const Description: string): string;
var
  { This is the position of next char in Description to work with,
    i.e. first FOffset-1 chars in Description are considered "done"
    ("done" means that their converted version is appended to Result) }
  FOffset: Integer;

  { This checks if some tag starts at Description[FOffset + 1].
    If yes then it returns true and sets
    -- TagHandlerObj to given tag object
    -- TagName to lowercased name of this tag (e.g. 'link')
    -- Parameters to params for this tag (text specified between '(' ')',
       parsed to the matching parenthesis)
    -- TagEnd to the index of *next* character in Description right
       after this tag (including it's parameters, if there were any)

    Note that it may also change it's var parameters even when it returns
    false; this doesn't harm anything for now, so I don't think there's
    a reason to correct this for now.

    In case some string looking as tag name (A-Za-z*) is here,
    but it's not a name of any existing tag,
    it not only returns false but also emits a warning for user. }
  function FindTag(var TagHandlerObj: TTagHandlerObj;
    var TagName: string; var Parameters: string;
    var TagEnd: Integer): Boolean;
  var
    i: Integer;
    BracketCount: integer;
    TagIndex: integer;
  begin
    Result := False;
    Parameters := '';
    i := FOffset + 1;

    while (i <= Length(Description)) and
          (Description[i] in ['A'..'Z', 'a'..'z']) do
      Inc(i);

    if i = FOffset + 1 then Exit; { exit with false }

    TagName := LowerCase(Copy(Description, FOffset + 1, i - FOffset - 1));
    TagEnd := i;

    if not FTags.Find(TagName, TagIndex) then
    begin
      DoMessage(1, mtWarning, 'Unknown tag name "%s"', [TagName]);
      Exit;
    end;

    TagHandlerObj := FTags.Objects[TagIndex] as TTagHandlerObj;
    Result := true;

    { OK, we found the correct tag.
      TagHandlerObj and TagName are already set.
      Now lets get the parameters, setting Parameters and TagEnd. }

    if (i <= Length(Description)) and (Description[i] = '(') then
    begin
      { Read Parameters to a matching parenthesis.
        Note that we didn't check here whether
        toParameterRequired in TagHandlerObj.TagOptions.
        Caller of FindTag will give a warning for user if it will
        receive some Parameters <> '' while
        toParameterRequired is *not* in TagHandlerObj.TagOptions }
      Inc(i);
      BracketCount := 1;
      repeat
        case Description[i] of
          '(': Inc(BracketCount);
          ')': Dec(BracketCount);
        end;
        Inc(i);
      until (i > Length(Description)) or (BracketCount = 0);
      if (BracketCount = 0) then begin
        Parameters := Copy(Description, TagEnd + 1, i - TagEnd - 2);
        TagEnd := i;
      end else
        DoMessage(1, mtWarning,
          'No matching closing parenthesis for tag "%s"', [TagName]);
    end else
    if toParameterRequired in TagHandlerObj.TagOptions then
    begin
      { Read Parameters to the end of Description or newline. }
      while (i <= Length(Description)) and
            (not (Description[i] in [#10, #13])) do
        Inc(i);
      Parameters := Trim(Copy(Description, TagEnd, i - TagEnd));
      TagEnd := i;
    end;
  end;

  { This function moves FOffset to the position of next '@' in Description
    starting at FOffset + 1 char (so this function always increases FOffset
    at least by one). Yes, this means that it always converts *at least* char
    Description[FOffset] to Result, but it doesn't care whether
    Description[FOffset] is '@' or not.
    Moves FOffset to Length(Decription)+1 if there are
    no more '@' chars.

    With moving FOffset, it also updates Result (of Execute method)
    accordingly, converting appropriate part of Description using
    ConvertString. }
  procedure Convert;
  var
    NewOffset: integer;
  begin
    NewOffset := PosEx('@', Description, FOffset + 1);
    if NewOffset = 0 then
      NewOffset := Length(Description)+1;

    Result := Result + DoInsertParagraphs(ConvertString(
      Copy(Description, FOffset, NewOffset - FOffset)));
    FOffset := NewOffset;
  end;

var
  ReplaceStr: string;
  TagName: string;
  Params: string;
  TagEnd: Integer;
  TagHandlerObj: TTagHandlerObj;
begin
  Result := '';
  FOffset := 1;

  while FOffset <= Length(Description) do
  begin
    if (Description[FOffset] = '@') and
       FindTag(TagHandlerObj, TagName, Params, TagEnd) then
    begin
      if Params <> '' then
      begin
        if toParameterRequired in TagHandlerObj.TagOptions then
        begin
          Unabbreviate(Params);
          if toRecursiveTags in TagHandlerObj.TagOptions then
            Params := Execute(Params); { recursively expand Params }
        end else
        begin
          { Note that in this case we ignore whether
            toRecursiveTags is in TagHandlerObj.TagOptions,
            we always behave like toRecursiveTags was not included.

            This is reported as a serious warning,
            because tag handler procedure will probably ignore
            passed value of Params and will set ReplaceStr to something
            unrelated to Params. This means that user input is completely
            discarded. So user should really correct it.

            I didn't mark this as an mtError only because some sensible
            output will be generated anyway. }
          DoMessage(1, mtWarning,
            'Tag "%s" is not allowed to have any parameters', [TagName]);
        end;
        ReplaceStr := ConvertString('@(' + TagName) + Params + ConvertString(')');
      end else
        ReplaceStr := ConvertString('@' + TagName);
      TagHandlerObj.Execute(Self, TagName, Params, ReplaceStr);

      Result := Result + ReplaceStr;
        FOffset := TagEnd;
    end else
    if (Description[FOffset] = '@') and
       (FOffset < Length(Description)) and
       (Description[FOffset + 1] = '@') then
    begin
      { convert '@@' to '@' }
      FOffset := FOffset + 2;
      Result := Result + '@';
    end else
      Convert;
  end;

  { Only for testing:
  Writeln('----');
  Writeln('Description was "', Description, '"');
  Writeln('Result is "', Result, '"');
  Writeln('----');}
end;

end.
